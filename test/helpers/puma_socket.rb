# frozen_string_literal: true

require 'socket'

module TestPuma

  # Note: no setup or teardown, make sure to initialize @ios = []
  #
  module PumaSocket
    GET_10 = "GET / HTTP/1.0\r\n\r\n"
    GET_11 = "GET / HTTP/1.1\r\n\r\n"

    HOST4 = '127.0.0.1'
    HOST6 = '[::1]'

    HOST = HOST4

    RESP_READ_LEN = 65_536
    RESP_READ_TIMEOUT = 10
    RESP_SPLIT = "\r\n\r\n"
    NO_ENTITY_BODY = Puma::STATUS_WITH_NO_ENTITY_BODY
    EMPTY_200 = [200, {}, ['']]

    SET_TCP_NODELAY = ::Socket.const_defined? :TCP_NODELAY

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
          if io.respond_to? :sysclose
            io.sync_close = true
            io.sysclose unless !io.closed?
          else
            io.close if io.respond_to?(:close) && !io.closed?
            if io.is_a?(File) && (path = io&.path) && File.exist?(path)
              File.unlink path
            end
          end
        rescue Errno::EBADF, Errno::ENOENT, IOError
        ensure
          io = nil
        end
      end
      @ios_to_close = []
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
    def send_http_read_resp_body(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: nil, timeout: nil, decode_chunked: nil, times: nil)
      skt = send_http req, host: host, port: port, path: path, ctx: ctx, session: session
      skt.read_body timeout, len: len, decode_chunked: decode_chunked, times: times
    end

    # Sends a request and returns the response string
    #
    def send_http_read_response(req = GET_11, host: nil, port: nil, path: nil, ctx: nil,
        session: nil, len: nil, timeout: nil, decode_chunked: nil, times: nil)
      skt = send_http req, host: host, port: port, path: path, ctx: ctx, session: session
      skt.read_response timeout, len: len, decode_chunked: decode_chunked, times: times
    end

    # Sends a request and returns the socket
    #
    def send_http(req = GET_11, host: nil, port: nil, path: nil, ctx: nil, session: nil)
      skt = new_socket host: host, port: port, path: path, ctx: ctx, session: session
      skt.syswrite req
      skt
    end

    READ_BODY = -> (timeout = nil, len: nil, decode_chunked: nil, times: nil) {
      self.read_response(timeout, len: len, decode_chunked: decode_chunked, times: times)
        .split(RESP_SPLIT, 2).last
    }

    READ_RESPONSE = -> (timeout = nil, len: nil, decode_chunked: nil, times: nil) do
      timeout ||= RESP_READ_TIMEOUT
      content_length = nil
      chunked = nil
      status = nil
      no_body = nil
      response = +''
      read_len = len || RESP_READ_LEN
      time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      time_end   = time_start + timeout
      if self.to_io.wait_readable timeout
        loop do
          begin
            part = self.read_nonblock(read_len, exception: false)
            case part
            when String
              times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_start if times
              status ||= part[/\AHTTP\/1\.[01] (\d{3})/, 1]
              if status
                no_body ||= NO_ENTITY_BODY.key? status.to_i || status.to_i < 200
              end
              if no_body && part.end_with?(RESP_SPLIT)
                return response << part
              end

              unless content_length || chunked
                chunked ||= part.downcase.include? "\r\ntransfer-encoding: chunked\r\n"
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
                    if body.end_with? "0\r\n\r\n"
                      if decode_chunked
                        response = TestPuma::PumaSocket.chunked_body hdrs, body
                      end
                      true
                    else
                      false
                    end
                  elsif !hdrs.empty? && !body.empty?
                    true
                  else
                    false
                  end
                return response if ret
              end
              sleep 0.000_1
            when :wait_readable
              to = time_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              self.to_io.wait_readable to
            when :wait_writable # :wait_writable for ssl
              to = time_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              self.to_io.wait_writable to
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

    def new_socket(host: nil, port: nil, path: nil, ctx: nil, session: nil)
      port  ||= @port || @tcp_port
      path  ||= @bind_path
      @host ||= host || HOST
      skt =
        if path && !port && !ctx
          UNIXSocket.new path.sub(/\A@/, "\0") # sub is for abstract
        elsif port && !path
          tcp = TCPSocket.new @host, port
          tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) if SET_TCP_NODELAY
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

    # Creates an array of sockets, sending a request on each
    def send_http_array(len, req = GET_11, dly: 0.000_1, max_retries: 5)
      Array.new(len) {
        retries = 0
        begin
          skt = send_http req
          sleep 0.000_1
          skt
        rescue Errno::ECONNREFUSED
          retries += 1
          if retries < max_retries
            retry
          else
            flunk 'Generate requests failed from Errno::ECONNREFUSED'
          end
        end
      }
    end


    # Reads an array of sockets that have already had requests sent.
    # @param skts [Array<Sockets]] an array of sockets that have already had
    #    requests sent
    # @return [Array<String, Class>] an array matching the order of the parameter
    #  `skts`, contains the response or the error class generated by the socket.
    #
    def read_response_array(skts, resp_count: nil)
      results = Array.new skts.length
      Thread.new do
        until skts.compact.empty?
          skts.each_with_index do |skt, idx|
            next if skt.nil?
            begin
              next unless skt.wait_readable 0.000_5
              if resp_count
                resp = skt.read_response.dup
                cntr = 0
                until resp.split(RESP_SPLIT).length == resp_count + 1 || cntr > 20
                  cntr += 1
                  Thread.pass
                  if skt.wait_readable 0.001
                    begin
                      resp << skt.read_response
                    rescue EOFError
                      break
                    end
                  end
                end
                results[idx] = resp
              else
                results[idx] = skt.read_response
              end
            rescue StandardError => e
              results[idx] = e.class.to_s
            end
            begin
              skt.close unless skt.closed? # skt.close may return Errno::EBADF
            rescue StandardError => e
              results[idx] ||= e.class.to_s
            end
            skts[idx] = nil
          end
        end
      end.join 15
      results
    end

    def self.chunked_body(hdrs, body)
      body = body.byteslice(0, body.bytesize - 5)   # remove terminating bytes
      decoded = String.new  # rubocop: disable Performance/UnfreezeString
      loop do
        size, body = body.split "\r\n", 2
        size = size.to_i 16

        decoded << body.byteslice(0, size)
        body = body.byteslice (size+2)..-1         # remove segment ending "\r\n"
        break if body.empty?
      end
      "#{hdrs}#{RESP_SPLIT}#{decoded}"
    end
  end
end
