require 'rubygems'
require 'json'
require 'eventmachine'
require 'digest/sha1'
require 'socket'

#   Message Format
#
# JSON METADATA in UTF-8 encoding
# NUL byte ('\0')
# PAYLOAD (raw bytes)
#
# The JSON metadata MUST contain at least the keys "size" and "type" to
# specify the length (in bytes) and type (mime) of the payload to follow.
#
# If the metadata contains the key "sha1", the value of that key is
# compared against the SHA1 hexdigest checksum of the payload (only,
# not including the leading NUL or metadata).o

module BiomineOE

  class AbstractConnection < EventMachine::Connection
    attr_reader :name

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
        data.force_encoding 'BINARY' if data.respond_to? :force_encoding
        if @payload_bytes_to_read
          if data.size >= @payload_bytes_to_read
            @buffer << data.slice!(0, @payload_bytes_to_read)
            payload = @buffer.join('')
            @buffer, @payload_bytes_to_read = [], nil
            begin
              receive_payload(payload)
            rescue Exception => e
              log "Invalid payload: #{e}"
              close_connection
            end
          else
            @buffer << data
            @payload_bytes_to_read -= data.size
            data = nil
          end
        else
          nul = data.index ?\0
          if nul
            @buffer << data.slice!(0, nul)
            data.slice!(0,1) # Remove the NUL
            metadata = @buffer.join('')
            @buffer = []
            begin
              receive_metadata(metadata)
            rescue Exception => e
              log "Invalid metadata: #{e}"
              close_connection
            end
          else
            @buffer << data
            data = nil
          end
        end
      end
    end

    # Called when an object has been received
    def receive_object(mimetype, payload, metadata)
    end

    private
    def receive_payload(payload)
      checksum = @metadata['sha1'].to_s
      unless checksum.empty?
        if BiomineOE.sha1(payload) != checksum
          log 'Checksum mismatch for payload'
          close_connection
          return
        end
      end
      mimetype = (@metadata['type'] || @metadata['mimetype']).to_s
      receive_object(mimetype, payload, @metadata)
      @metadata = nil
    end

    def receive_metadata(metadata)
      if metadata.respond_to? :force_encoding
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
        log "Metadata not valid JSON: #{e}"
      end
    end

    def log(msg)
      BiomineOE.log self, msg
    end
  end

  def BiomineOE.sha1(data)
    Digest::SHA1.hexdigest data
  end

  def BiomineOE.log(sender, msg)
    name = (sender.respond_to? :name) ? sender.name.to_s : ''
    $stderr.puts "#{sender.class.to_s} (#{name}): #{msg}"
  end

end
