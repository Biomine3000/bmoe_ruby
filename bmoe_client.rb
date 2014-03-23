#   Client Implementation

require 'bmoe'
require 'base64'

module BiomineOE

  TERMINAL_CHARACTER_SET = 'UTF-8'
  CLIENT_CHARACTER_SET = 'UTF-8'

  class ClientConnection < AbstractConnection
    def initialize
      #self.comm_inactivity_timeout = 10
    end

    # Called by event machine on connect
    def connection_completed
      log 'Connected'
      #self.comm_inactivity_timeout = 0
    end

    # Called by event machine on disconnect
    def unbind
      log 'Disconnected'
      EventMachine.stop
    end

    def output(msg)
      puts msg
    end

    def receive_object(metadata, payload)
      event = metadata['event']
      if event
        case event
        when 'ping'
          pong = { 'event' => 'pong' }
          oid = metadata['id']
          pong['in-reply-to'] = oid if oid
          route = metadata['route']
          if route.kind_of?(Array)
            rid = route.first || metadata['routing-id']
            pong['to'] = rid if rid
          end
          json = send_object(pong)
          #output "<< PING: #{metadata}"
          #output ">> PONG: #{json}"
          return
        else
        end
      end
      mimetype = metadata['type'].to_s
      output "<< #{metadata}#{payload ? "(#{payload.size} bytes payload)" : ''}\n"
      return unless mimetype =~ /^text\//

      if payload.size > 0
        sha1 = metadata['sha1']
        if sha1 && sha1 != BiomineOE.sha1(payload)
          output "<< CHECKSUM MISMATCH:"
        end
      end

      # Character set conversion in Ruby 1.9+
      if payload.respond_to? :force_encoding
        charset = mimetype[/charset=[^ ]+/].to_s
        unless charset.empty?
          charset.slice! /^charset="?/
          charset.slice! /".*$/
          begin
            payload.force_encoding charset
          rescue Exception => e
            log "Invalid character set \"#{charset}\": #{e}"
            return
          end
          unless payload.valid_encoding?
            log "Encoding does not match character set \"#{charset}\""
            return
          end
        else
          payload.force_encoding 'UTF-8'
          payload.force_encoding 'ISO-8859-15' unless payload.valid_encoding?
        end

        # Recode to UTF-8
        begin
          payload = payload.encode TERMINAL_CHARACTER_SET
        rescue Exception => e
          log "Encoding to #{TERMINAL_CHARACTER_SET} failed: #{e}"
          return
        end
      end

      output "<#{metadata['routing-id']}> #{payload}\n"
    end
  end

  class KeyboardInput < EventMachine::Connection
    include BiomineOE::AbstractNetworkNode
    include EventMachine::Protocols::LineText2

    def initialize(server)
      @server = server
      @name = 'keyboard'
    end

    def unbind
      output ">> Closing connection"
      @server.close_connection_after_writing
    end

    def output(msg)
      puts msg
    end

    def send_data(data)
      @server.send_data(data)
    end

    def send_file(line, natures = [])
      mimetype, payload = BiomineOE.file_type_and_contents(line)
      if payload
        filename = File.basename(line)
        natures << 'file' unless natures.include?('file')
        metadata = { 'type' => mimetype, 'filename' => filename,
                     'natures' => natures }
        output ">> #{metadata}:(#{payload.size} bytes)"
        send_object(metadata, payload)
      else
        output "ERROR: #{line}:#{mimetype}"
      end
    end

    def send_json(line, natures = [])
      payload = line.slice!(/[^}]*$/)
      json = nil
      begin
        json = JSON.parse(line)
        if payload.slice!(/^[Bb](ase)?64:/)
          payload = Base64.decode64(payload)
        end
      rescue Exception => e
        output "ERROR: #{e}"
        return
      end
      json['natures'] ||= natures unless natures.empty?
      output ">> #{json}#{payload.inspect}"
      send_object(json, payload || '')
    end

    def send_subscribe(subscriptions)
      metadata = { 'event' => 'routing/subscribe',
                   'subscriptions' => (subscriptions || []) }
      json = send_object(metadata)
      output ">> #{json}"
    end

    def random_encoding(line)
      old_encoding = line.encoding.to_s.downcase
      retries_remaining = 10
      encodings = Encoding.list
      begin
        encoding = old_encoding
        while encoding.to_s.downcase == old_encoding
          encoding = encodings.sample
        end
        line = line.encode(encoding)
        return line
      rescue Exception => e
        if retries_remaining > 0
          retries_remaining -= 1
          retry
        end
        output "ERROR: #{e}"
      end
      return nil
    end

    def natures_from_line(line)
      nat = line.slice!(/^\s*(#[a-zA-Z]+\s+)*/)
      natures = nat.split.find_all { |word| word =~ /^#[a-zA-Z]+$/ }
      natures.collect! { |nature| nature[1..-1] }
      natures.uniq!
      return natures, line
    end

    def receive_line(line)
      if line.respond_to?(:force_encoding)
        line.force_encoding TERMINAL_CHARACTER_SET
        line = line.encode CLIENT_CHARACTER_SET
      end
      natures, line = natures_from_line(line)
      line.strip!
      return if line.empty? && natures.empty?
      field = line[/^\S+/]
      case field
      when '/ping'
        json = ping
        output ">> #{json}"
        return
      when '/quit'
        @server.close_connection_after_writing
        return
      when '/subscribe'
        line.gsub!(',', ' ')
        return send_subscribe(line.split[1..-1])
      when '/json'
        line.sub!(/^\S+\s*/, '')
        return send_json(line, natures)
      when '/file'
        line.sub!(/^\S+\s*/, '')
        return send_file(line, natures)
      when '/enc'
        line.sub!(/^\S+\s*/, '')
        line = random_encoding(line)
        return unless line
      when '/encode'
        line.sub!(/^\S+\s*/, '')
        encoding = line.slice!(/^\S+\s*/).to_s.strip
        begin
          line = line.encode encoding
        rescue Exception => e
          output "ERROR: #{e}"
          return
        end
      else
      end
      natures << 'message' unless natures.include?('message')
      charset = line.respond_to?(:encoding) ? line.encoding : nil
      metadata = {
        'type' => "text/plain#{charset ?  "; charset=#{charset}" : ''}",
        'natures' => natures
      }
      output ">> #{metadata}:#{line.inspect}" if natures.size > 1
      send_object(metadata, line)
    end
  end

  # Returns mimetype, payload - on error payload will be nil and metadata
  # is a string describing the error.
  def BiomineOE.file_type_and_contents(filename)
    mimetype, payload = nil, nil
    begin
      IO.popen(['file', '--brief', '--mime', filename.to_s],
               :in => :close, :err => :close) do |pipe|
         mimetype = pipe.read.to_s.strip
         pipe.close
         if $?.to_i == 0 && mimetype =~ /^[a-zA-Z-]+\/[^()\/]+$/
           mimetype.sub!(/;\s*charset=(binary|us-ascii)$/, '')
           payload = File.open(filename, 'rb') { |f| f.read }
         end
      end
    rescue Exception => e
      mimetype, payload = e.to_s, nil
    end
    return mimetype, payload
  end

end
