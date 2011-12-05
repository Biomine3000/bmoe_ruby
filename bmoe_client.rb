#   Client Implementation

require 'bmoe'

module BiomineOE

  TERMINAL_CHARACTER_SET = 'UTF-8'
  CLIENT_CHARACTER_SET = 'UTF-8'

  class ClientConnection < AbstractConnection
    # Called by event machine on disconnect
    def unbind
      log 'Disconnected'
      EventMachine.stop
    end

    def output(msg)
      puts msg
    end

    def receive_object(mimetype, payload, metadata)
      log "Received \"#{mimetype}\" (#{payload.size} bytes)"
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
          payload = payload.encode 'UTF-8'
        rescue Exception => e
          log "Encoding to UTF-8 failed: #{e}"
          return
        end
      end

      output "Message text: #{payload}\n"
    end
  end

  class KeyboardInput < EventMachine::Connection
    include EventMachine::Protocols::LineText2

    def initialize(server)
      @server = server
    end

    def receive_line(line)
      line.strip!
      return if line.empty?
      charset = (line.respond_to? :force_encoding) ? CLIENT_CHARACTER_SET : nil
      if line.respond_to? :force_encoding
        line.force_encoding TERMINAL_CHARACTER_SET
        line.encode CLIENT_CHARACTER_SET
      end
      json = { 'type' => "text/plain#{charset ?  "; charset=#{charset}" : ''}",
               'size' => line.bytesize,
               'sha1' => BiomineOE::sha1(line)
      }.to_json
      puts "Sending with metadata: #{json}"
      @server.send_data(json)
      @server.send_data("\0")
      @server.send_data(line)
    end
  end

end
