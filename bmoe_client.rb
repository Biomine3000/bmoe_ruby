#   Client Implementation

require 'bmoe'

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
          rid = metadata['routing-id']
          pong['to'] = rid if rid
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
      output "# Closing connection"
      @server.close_connection_after_writing
    end

    def output(msg)
      puts msg
    end

    def send_data(data)
      @server.send_data(data)
    end

    def receive_line(line)
      line.strip!
      #return if line.empty?
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
        metadata = { 'event' => 'routing/subscribe',
                     'subscriptions' => line.split[1..-1] }
        json = send_object(metadata)
        output ">> #{json}"
        return
      else
      end
      charset = (line.respond_to? :force_encoding) ? CLIENT_CHARACTER_SET : nil
      if line.respond_to? :force_encoding
        line.force_encoding TERMINAL_CHARACTER_SET
        line = line.encode CLIENT_CHARACTER_SET
      end
      metadata = {
        'type' => "text/plain#{charset ?  "; charset=#{charset}" : ''}",
        'natures' => [ 'message' ]
      }
      send_object(metadata, line)
    end
  end

end
