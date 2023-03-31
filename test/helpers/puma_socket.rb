# frozen_string_literal: true

module PumaTest

  # Note: no setup or teardown, make sure to initialize @ios = []
  #
  module PumaSocket
    RESP_READ_LEN = 65_536
    RESP_READ_TIMEOUT = 10
    RESP_SPLIT = "\r\n\r\n"
    HOST = '127.0.0.1'

    def before_setup
      @ios_to_close ||= []
      @port = nil
      super
    end

    def after_teardown
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
      while true
        skt.wait_readable 1
        line = skt.gets
        break if line == "\r\n"
        headers << line.strip
      end

      headers
    end

    def send_http_and_read(req, port: nil, path: nil)
      skt = send_http req, port: port, path: path
      skt.read_response
    end

    def send_http(req, port: nil, path: nil)
      skt = new_connection port: port, path: path
      skt.syswrite req
      skt
    end

    READ_BODY = -> (timeout = nil) {
      self.read_response(timeout).split(RESP_SPLIT, 2).last
    }

    READ_RESPONSE = -> (timeout = nil) do
      timeout ||= RESP_READ_TIMEOUT
      content_length = nil
      chunked = nil
      response = +''
      t_st = Process.clock_gettime Process::CLOCK_MONOTONIC
      if self.to_io.wait_readable timeout
        loop do
          begin
            part = self.read_nonblock(RESP_READ_LEN, exception: false)
            case part
            when String
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
            if timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st
              raise Timeout::Error, 'Client Read Timeout'
            end
          end
        end
      else
        raise Timeout::Error, 'Client Read Timeout'
      end
    end

    REQ_WRITE = -> (str) { self.syswrite str }

    def new_connection(port: nil, path: nil)
      port  ||= @port
      @host ||= HOST
      skt = path ? UNIXSocket.new(path) : TCPSocket.new(@host, port)
      skt.define_singleton_method :read_response, READ_RESPONSE
      skt.define_singleton_method :read_body, READ_BODY
      skt.define_singleton_method :<<, REQ_WRITE
      @ios_to_close << skt
      skt
    end
  end
end
