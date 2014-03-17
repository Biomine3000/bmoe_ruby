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
      @em = EventMachine.start_server(ip, port, NetworkNode) do |c|
        @connections << c
        c.connected(self)
        send_routing_announcement
      end
      EventMachine.add_periodic_timer(300) do
        if @routing_changed
          send_routing_announcement
          @routing_changed = false
        end
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

    # Connect to another server
    def connect_to_server(ip, port)
      log "Linking with server #{ip}:#{port}"
      EventMachine.connect(ip, port, NetworkNode) do |c|
        @connections << c
        c.role = :server
        c.name = "SERVER[#{ip}:#{port}]"
        c.connected(self)
        send_server_subscription(c)
      end
    end

    # Route an object
    def route_object(metadata, payload = nil, from = nil, servers_only = false)
      # ensure every object has an id
      oid = metadata['id']
      unless oid.kind_of?(String) && !oid.empty?
        oid = BiomineOE.object_id_for(metadata, payload)
        metadata['id'] = oid
      end
      from = from.respond_to?(:routing_id) ? from.routing_id : from.to_s

      metadata['routing-id'] ||= from if from

      # add ourselves and the immediately connected client to the route
      route = metadata['route']
      if route.kind_of? Array
        route << from unless from.empty? || route.include?(from)
        route << @routing_id unless route.include?(@routing_id)
      else
        route = from ? [ from, @routing_id ] : [ @routing_id ]
      end

      to = metadata['to']
      to = (to.kind_of?(String) ? [ to ] : nil) unless to.kind_of?(Array)

      targets = []
      recipient_count = 0
      @connections.each do |c|
        rid = c.routing_id
        next if to && !to.include?(rid)
        recipient_count += 1
        next if route.include?(rid)
        next if servers_only && !c.server?
        if c.subscribed_to?(metadata, payload)
          targets << c
        end
      end
      if to && recipient_count < to.size
        # forward object to other servers if there were unreached recipients
        @connections.each do |c|
          if c.server? && !route.include?(c.routing_id) &&
             c.subscribed_to?(metadata, payload)
            targets << c
          end
        end
      end
      targets.each do |c|
        route << c.routing_id if c.server?
      end
      #metadata['route'] = route
      targets.each do |target|
        # FIXME: The following line is only for legacy server compatibility:
        metadata['route'] = route - [ target.routing_id ]
        target.send_object(metadata, payload)
      end
      #log "Routed: #{json}\n\t-> #{targets.collect { |t| t.to_s }}"
      targets
    end

    # Handle a routing/subscribe event
    def routing_subscribe(client, metadata)
      subscription_created = client.subscriptions.nil?
      was_server = client.server?
      client.role = CONNECTION_ROLES[metadata['role']] unless was_server
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
      client.log "Subscribed: #{metadata}"

      # reply to subscription
      reply = { 'event' => 'routing/subscribe/reply',
                'routing-id' => client.routing_id }
      oid = metadata['id']
      reply['in-reply-to'] = oid if oid
      role = client.role
      reply['role'] = role if role && role != :client
      client.send_object(reply)

      # subscribe back to a server that has connected to us
      send_server_subscription(client) if client.server? && !was_server

      # notify others (why?)
      if subscription_created && client.subscriptions
        notification = { 'event' => 'routing/subscribe/notification',
                         'routing-id' => client.routing_id,
                         'route' => [ client.routing_id, @routing_id ] }
        route_object(notification)
        @routing_changed = true
      end
      reply
    end

    # Send a subscription (to another server)
    def send_server_subscription(c)
      subscribe = { 'event' => 'routing/subscribe',
                    'role' => 'server',
                    'subscriptions' => [ '*' ],
                    'routing-id' => @routing_id,
                    'route' => [ @routing_id ] }
      subscribe['id'] = BiomineOE.object_id_for(subscribe)
      log "Subscribing to #{c}: #{subscribe}"
      c.send_object(subscribe)
    end

    # Send a neighbor announcement to connected servers
    def send_routing_announcement
      neighbors = []
      @connections.each { |c| neighbors << c.routing_id if c.subscriptions }
      return if neighbors.empty?
      announcement = { 'event' => 'routing/announcement/neighbors',
                       'neighbors' => neighbors }
      log "Routing announcement: #{announcement}"
      route_object(announcement, nil, @routing_id, true)
    end

    # Called when an object is received
    def receive_object(client, metadata, payload)
      #route = metadata['route']
      #return if route.respond_to?(:include?) && route.include?(@routing_id)
      event = metadata['event']
      if event
        case event
        when 'routing/subscribe'
          return routing_subscribe(client, metadata)
        when 'routing/subscribe/reply'
          if client.server?
            client.log "#{event}: #{metadata}"
            return
          end
        when 'routing/subscribe/notification', 'routing/disconnect'
          client.log "#{event}: #{metadata}"
          @routing_changed = true
        when /routing\/*/
          unless metadata['to']
            # route other routing info only to servers
            return route_object(metadata, payload, client, true)
          end
        else
          if client.server?
            client.log "#{event}: #{metadata}"
          end
        end
      else
        client.log "#{metadata['type']} (#{payload.size} bytes)"
      end
      route_object(metadata, payload, client)
    end

    # Called by client on disconnect
    def disconnected(client)
      @connections.delete(client)
      if client.subscriptions
        notification = { 'event' => 'routing/disconnect' }
        route_object(notification, nil, client)
        @routing_changed = true
      end
    end

    def to_s
      self.name
    end

    private
    def log(msg)
      BiomineOE.log self, msg
    end
  end

  class NetworkNode < AbstractConnection
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
        if rule.respond_to?(:each)
          # nested arrays short-circuit on match
          return true if message_subscribed?(msg, rule)
          next
        end
        next unless rule.kind_of? String
        is_negative_rule = rule.start_with? '!'
        rule = rule[1..-1] if is_negative_rule
        if rule.start_with? '#'
          natures = msg['natures']
          if natures.respond_to?(:each)
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
      end
      pass
    end
  end

end
