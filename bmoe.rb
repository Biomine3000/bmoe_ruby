# Biomine Object Exchange

require 'rubygems'
require 'json'
require 'eventmachine'
require 'digest/sha1'
require 'socket'
require 'securerandom'

#   Message Format
#
# JSON METADATA in UTF-8 encoding
# NUL byte ('\0')
# PAYLOAD (raw bytes)
#
# The JSON metadata MUST contain at least the keys "size" and "type" to
# specify the length (in bytes) and type (mime) of the payload to follow.

module BiomineOE

  CONNECTION_ROLES = {
    'server' => :server,
    'client' => :client,
    'service' => :service
  }

  module AbstractNetworkNode
    attr_accessor :name
    attr_accessor :role
    attr_accessor :username
    attr_reader :last_sent
    attr_reader :last_received

    # Return true for servers
    def server?
      @role == :server
    end

    # Called when an object has been received
    def receive_object(metadata, payload)
      @last_received = Time.now
    end

    # Send an object
    def send_object(metadata, payload = nil)
      if metadata.kind_of?(Hash)
        if payload.respond_to?(:size)
          metadata['size'] = payload.respond_to?(:bytesize) ? payload.bytesize : payload.size
        else
          metadata.delete('size')
          payload = nil
        end
        metadata = metadata.to_json
      end
      send_data(metadata)
      send_data("\0")
      send_data(payload) if payload
      @last_sent = Time.now
      metadata
    end

    # Send a ping
    def ping
      metadata = { 'event' => 'ping' }
      metadata['to'] = @routing_id if @routing_id
      metadata['id'] = BiomineOE.object_id_for(metadata)
      send_object(metadata)
    end

    def log(msg)
      BiomineOE.log self, msg
    end

    def seconds_since_sent
      @last_sent ? (Time.now - @last_sent) : (1.0/0.0)
    end

    def seconds_since_received
      @last_received ? (Time.now - @last_received) : (1.0/0.0)
    end

    def routing_id
      unless @routing_id.kind_of?(String) && !@routing_id.empty?
        # Generate routing id if none exists
        @routing_id = BiomineOE.routing_id_for(self)
      end
      @routing_id
    end

    def routing_id=(rid)
      @routing_id = rid
    end
  end

  class AbstractConnection < EventMachine::Connection
    include AbstractNetworkNode

    # Called by event machine on connect
    def post_init
      if (peername = get_peername)
        port, ip = Socket.unpack_sockaddr_in(peername)
        @name = "#{ip}:#{port}"
      else
        @name = 'connection'
      end
      @buffer, @metadata, @payload_bytes_to_read = [], nil, nil
    end

    # Called by event machine on data input
    def receive_data(data)
      while not (data.nil? or data.empty?)
        data.force_encoding 'BINARY' if data.respond_to?(:force_encoding)
        unless @payload_bytes_to_read
          nul = data.index ?\0
          if nul
            @buffer << data.slice!(0, nul)
            data.slice!(0,1) # Remove the NUL
            metadata = @buffer.join('')
            @buffer = []
            begin
              receive_metadata(metadata)
            rescue Exception => e
              log_exception(e, 'Invalid metadata', metadata)
              close_connection
              return
            end
          else
            @buffer << data
            data = nil
          end
        end
        if @payload_bytes_to_read
          if data.size >= @payload_bytes_to_read
            @buffer << data.slice!(0, @payload_bytes_to_read)
            payload = @buffer.join('')
            @buffer, @payload_bytes_to_read = [], nil
            begin
              receive_payload(payload)
            rescue Exception => e
              log_exception(e, 'Invalid payload')
              close_connection
              return
            end
          else
            @buffer << data
            @payload_bytes_to_read -= data.size
            data = nil
          end
        end
      end
    end

    def to_s
      self.name || self.routing_id
    end

    private
    def log_exception(e, msg = nil, obj = nil)
      bt = e.backtrace.clone
      bt << obj.inspect if obj
      log "#{msg}#{msg ? ':' : ''} #{e}\n\t#{e.backtrace.join("\n\t")}"
    end

    def receive_payload(payload)
      begin
        receive_object(@metadata, payload)
      rescue Exception => e
        log_exception(e, 'Error receiving object', @metadata)
      end
      @metadata = nil
    end

    def receive_metadata(metadata)
      if metadata.respond_to?(:force_encoding)
        metadata.force_encoding "UTF-8"
        unless metadata.valid_encoding?
          log 'Metadata not valid UTF-8'
          close_connection
        end
      end
      begin
        @metadata = JSON.parse(metadata)
        @payload_bytes_to_read = @metadata['size'].to_i
      rescue Exception => e
        log_exception(e, 'Metadata not valid JSON', metadata)
      end
    end
  end

  def BiomineOE.sha1(data)
    Digest::SHA1.hexdigest data
  end

  def BiomineOE.log(sender, msg)
    $stderr.puts "#{sender.class.to_s} (#{sender}): #{msg}"
  end
  
  def BiomineOE.routing_id_for(node)
    SecureRandom.uuid
  end

  def BiomineOE.object_id_for(metadata, payload = nil)
    SecureRandom.uuid
  end

end

# Simple wildcard matching: allow a single * at the end to match anything,
# and don't match non-String objects, compare case-insensitively

class String
  def abboe_wildcard_matches?(item)
    return false unless item.kind_of?(String)
    if self.end_with?('*')
      # wildcard at the end
      item.downcase.start_with?(self[0..-2].downcase)
    else
      # exact case-insensitive
      self.casecmp(item) == 0
    end
  end
end
