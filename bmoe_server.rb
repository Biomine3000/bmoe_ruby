# Server Implementation

require 'bmoe'

module BiomineOE

  class Server
    attr_reader :name

    # Start listening
    def start(ip, port)
      @connections = []
      @routing_id = BiomineOE.routing_id_for(self)
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

    def route_object(metadata, payload, from = nil)
      # ensure every object has an id
      oid = metadata['id']
      unless oid.kind_of?(String) && !oid.empty?
        oid = BiomineOE.object_id_for(metadata, payload)
        metadata['id'] = oid
      end
      from = from.respond_to?(:routing_id) ? from.routing_id : from.to_s

      # add ourselves and the immediately connected client to the route
      route = metadata['route']
      if route.kind_of? Array
        route << @routing_id
        route << from unless from.empty?
      else
        route = from ? [ @routing_id, from ] : [ @routing_id ]
      end
      metadata['route'] = route

      to = metadata['to']
      to = (to.kind_of?(String) ? [ to ] : nil) unless to.respond_to?(:include?)

      recipient_count, sent_count = 0, 0
      @connections.each do |c|
        rid = c.routing_id
        next if to && !to.include?(rid)
        recipient_count += 1
        next if route.include?(rid)
        if c.subscribed_to?(metadata, payload)
          c.send_object(metadata, payload)
          sent_count += 1
        end
      end
      if to && recipient_count < to.size
        # forward object to other servers if there were unreached recipients
        @connections.each do |c|
          if c.server? && !route.include?(c.routing_id) &&
             c.subscribed_to?(metadata, payload)
            c.send_object(metadata, payload)
            sent_count += 1
          end
        end
      end
      sent_count
    end

    def routing_subscribe(client, metadata)
      client.role = CONNECTION_ROLES[metadata['role']]
      client.subscriptions = metadata['subscriptions']
      rid = metadata['routing-id']
      client.routing_id = rid if rid.kind_of?(String) && !rid.empty?
      name = metadata['name']
      if name.kind_of? String
        unless @connections.collect { |c| c.name }.include?(name)
          client.name = name
        end
      end
      username = metadata['user']
      client.username = username if username.kind_of?(String) && !username.empty?
      log "\"#{client.name}\" subscriptions: #{client.subscriptions}"
    end

    def receive_object(client, metadata, payload)
      route = metadata['route']
      return if route.respond_to?(:include?) && route.include?(@routing_id)
      event = metadata['event']
      if event
        log "Received event \"#{event}\" from #{client.name}"
        case event
        when 'routing/subscribe'
          return routing_subscribe(client, metadata)
        else
        end
      else
        log "Received \"#{metadata['type'].to_s}\" (#{payload.size} bytes) from #{client.name}"
      end
      route_object(metadata, payload, client)
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
    attr_accessor :subscriptions

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

    def subscribed_to?(metadata, payload)
      message_subscribed?(metadata,
        @subscriptions.respond_to?(:each) ? @subscriptions : [ @subscriptions ]
      )
    end

    def receive_object(metadata, payload)
      @server.receive_object(self, metadata, payload) if @server
    end

    def routing_id
      unless @routing_id.kind_of?(String) && !@routing_id.empty?
        @routing_id = BiomineOE.routing_id_for(self)
      end
      @routing_id
    end

    private
    def message_subscribed?(msg, subscriptions)
      pass = false
      subscriptions.each do |rule|
        if rule.respond_to? :each
          # nested arrays short-circuit on match
          return true if message_subscribed?(msg, rule)
          next
        end
        next unless rule.kind_of? String
        is_negative_rule = rule.start_with? '!'
        rule = rule[1..-1] if is_negative_rule
        if rule.start_with? '#'
          natures = msg['natures']
          if natures.respond_to? :each
            rule = rule[1..-1]
            natures.each do |nature|
              if rule.abboe_wildcard_matches?(nature)
                pass = !is_negative_rule
                break
              end
            end
          end
        elsif rule.start_with? '@'
          rule = rule[1..-1]
          pass = !is_negative_rule if rule.abboe_wildcard_matches?(msg['event'])
          # if msg is not an event, the resulting nil will not match '@*' rule
        else
          # important: '*' rule must match everything, hence || ''
          type = (msg['type'].to_s)[/^[^ ;]*/]
          pass = !is_negative_rule if rule.abboe_wildcard_matches?(type)
        end
        puts "Rule #{rule}: #{pass}"
      end
      pass
    end
  end

end
