#   Server Implementation
#
# This server simply echoes all received messages to all clients.
#
# TODO: Allow clients to only subscribe to certain (types/etc) of messages.
# TODO: Allow clients to identify themselves.
# TODO: Store messages for sending to clients connecting after receipt of message

require 'bmoe'

module BiomineOE

  class Server
    attr_reader :name

    # Start listening
    def start(ip, port)
      @connections = []
      @name = "#{ip}:#{port}"
      log 'Starting'
      @em = EventMachine.start_server(ip, port, ConnectionOnServer) do |c|
        @connections << c
        c.connected(self)
      end
    end

    # Stop the server (and EventMachine)
    def stop
      log 'Stopping'
      EventMachine.stop_server(@em)
      @connections.each { |c| c.close_connection_after_writing }
      EventMachine.add_periodic_timer(1) do
        if @connections.empty?
          EventMachine.stop
          true
        else
          log "Waiting for #{@connections.size} connections to close"
          false
        end
      end
    end

    def receive_object(client, mimetype, payload, metadata)
      log "Received \"#{mimetype}\" (#{payload.size} bytes) from #{client.name}"
      unless metadata.has_key? 'sha1'
        metadata = metadata.clone
        metadata['sha1'] = BiomineOE.sha1(payload)
      end
      metadata = metadata.to_json
      @connections.each do |c|
        unless c == client
          log "Sent package from #{client.name} to #{c.name}"
          c.send_data(metadata)
          c.send_data("\0")
          c.send_data(payload)
        end
      end
    end

    # Called by client on disconnect
    def disconnected(client)
      @connections.delete(client)
    end

    private
    def log(msg)
      BiomineOE.log self, msg
    end
  end

  class ConnectionOnServer < AbstractConnection
    # Called by server on connect
    def connected(server)
      @server = server
      log 'Connected'
    end

    # Called by event machine on disconnect
    def unbind
      log 'Disconnected'
      @server.disconnected(self) if @server
    end

    def receive_object(mimetype, payload, metadata)
      @server.receive_object(self, mimetype, payload, @metadata) if @server
    end
  end

end
