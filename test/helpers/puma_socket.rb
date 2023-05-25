# frozen_string_literal: true

module TestPuma

  # Note: no setup or teardown, make sure to initialize @ios = []
  #
  module PumaSocket
    GET_10 = "GET / HTTP/1.0\r\n\r\n"
    GET_11 = "GET / HTTP/1.1\r\n\r\n"

    HOST = '127.0.0.1'
    RESP_READ_LEN = 65_536
    RESP_READ_TIMEOUT = 10
    RESP_SPLIT = "\r\n\r\n"
    NO_ENTITY_BODY = Puma::STATUS_WITH_NO_ENTITY_BODY

    def before_setup
      @ios_to_close ||= []
      @tcp_port = nil
      @bind_path = nil
      @port = nil
      super
    end

    def after_teardown
      return if skipped?
      # Errno::EBADF raised on macOS
      @ios_to_close.each do |io|
        begin
          io.close if io.respond_to?(:close) && !io.closed?
          File.unlink io.path if io.is_a? File
        rescue Errno::EBADF
        ensure
          io = nil
        end
      end
      super
    end

    def header(skt)
      headers = []
      while skt.wait_readable 5
        line = skt.gets
        break if line == "\r\n"
        headers << line.strip
      end

      headers
    end

    # rubocop: disable Metrics/ParameterLists

    # Sends a request and returns the response body
    #
    def send_http_read_resp_body(req, host: nil, port: nil, path: nil, ctx: nil, session: nil, len: nil, timeout: nil)
      skt = send_http req, host: host, port: port, path: path, ctx: ctx, session: session
      skt.read_body timeout, len: len
    end

    # Sends a request and returns the response string
    #
    def send_http_read_response(req, host: nil, port: nil, path: nil, ctx: nil, session: nil, len: nil, timeout: nil)
      skt = send_http req, host: host, port: port, path: path, ctx: ctx, session: session
      skt.read_response timeout, len: len
    end

    # Sends a request and returns the socket
    #
    def send_http(req, host: nil, port: nil, path: nil, ctx: nil, session: nil)
      skt = new_connection host: host, port: port, path: path, ctx: ctx, session: session
      skt.syswrite req
      skt
    end

    READ_BODY = -> (timeout = nil, len: nil) {
      self.read_response(timeout, len: len).split(RESP_SPLIT, 2).last
    }

    READ_RESPONSE = -> (timeout = nil, len: nil) do
      timeout ||= RESP_READ_TIMEOUT
      content_length = nil
      chunked = nil
      status = nil
      no_body = nil
      response = +''
      time_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      read_len = len || RESP_READ_LEN

      if self.to_io.wait_readable timeout
        loop do
          begin
            part = self.read_nonblock(read_len, exception: false)
            case part
            when String
              status ||= part[/\AHTTP\/1\.[01] (\d{3})/, 1]
              if status
                no_body ||= NO_ENTITY_BODY.key? status.to_i || status.to_i < 200
              end
              if no_body && part.end_with?(RESP_SPLIT)
                return response << part
              end

              unless content_length || chunked
                chunked ||= part.include? "\r\nTransfer-Encoding: chunked\r\n"
                content_length = (t = part[/^Content-Length: (\d+)/i , 1]) ? t.to_i : nil
              end

              response << part
              hdrs, body = response.split RESP_SPLIT, 2
              unless body.nil?
                # below could be simplified, but allows for debugging...
                ret =
                  if content_length
                    body.bytesize == content_length
                  elsif chunked
                    body.end_with? "0\r\n\r\n"
                  elsif !hdrs.empty? && !body.empty?
                    true
                  else
                    false
                  end
                if ret
                  return response
                end
              end
              sleep 0.000_1
            when :wait_readable, :wait_writable # :wait_writable for ssl
              sleep 0.000_2
            when nil
              if response.empty?
                raise EOFError
              else
                return response
              end
            end
            if time_end < Process.clock_gettime(Process::CLOCK_MONOTONIC)
              raise Timeout::Error, 'Client Read Timeout'
            end
          end
        end
      else
        raise Timeout::Error, "Client 'wait_readable' Timeout"
      end
    end

    REQ_WRITE = -> (str) { self.syswrite str }

    def new_ctx(&blk)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      yield ctx if blk
      ctx
    end

    def new_connection(host: nil, port: nil, path: nil, ctx: nil, session: nil)
      port  ||= @port || @tcp_port
      path  ||= @bind_path
      @host ||= host || HOST
      skt =
        if path && !port && !ctx
          UNIXSocket.new path.sub(/\A@/, "\0") # sub is for abstract
        elsif port && !path
          tcp = TCPSocket.new @host, port
          if ctx
            ::OpenSSL::SSL::SSLSocket.new tcp, ctx
          else
            tcp
          end
        else
          raise 'port or path must be set!'
        end
      skt.define_singleton_method :read_response, READ_RESPONSE
      skt.define_singleton_method :read_body, READ_BODY
      skt.define_singleton_method :<<, REQ_WRITE
      @ios_to_close << skt
      if ctx
        @ios_to_close << tcp
        skt.session = session if session
        skt.connect
      end
      skt
    end

    # Reads an array of sockets that have already had requests sent.
    # @param skts [Array<Sockets]] an array of sockets that have already had
    #    requests sent
    # @return [Array<String, Class>] an array matching the order of the parameter
    #  `skts`, contains the response or the error class generated by the socket.
    #
    def read_response_array(skts, len = nil, read_again: false)
      results = len ? Array.new(len) : []
      until skts.compact.empty?
        skts.each_with_index do |skt, idx|
          next if skt.nil?
          if skt.wait_readable 0.000_5
            begin
              if read_again
                body = skt.read_response.dup
                if skt.wait_readable 0.000_5
                  begin
                    body << skt.read_response
                  rescue EOFError
                  end
                end
                results[idx] = body
              else
                results[idx] = skt.read_response
              end
            rescue StandardError => e
              results[idx] = e.class.to_s
            end
            skts[idx] = nil
          end
        end
      end
      results
    end

    private
    def no_body(status)

    end
  end
end
