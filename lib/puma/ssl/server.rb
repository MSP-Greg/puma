# frozen_string_literal: true

require 'openssl'

module Puma
  module SSL
    class Server < OpenSSL::SSL::SSLServer
      def accept_nonblock
        tcp_socket = @svr.accept_nonblock
        ssl_socket = OpenSSL::SSL::SSLSocket.new tcp_socket, @ctx
        ssl_socket.sync_close = true
        t_st = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        time_end = t_st + 2.0
        begin
          ssl_socket.accept_nonblock
        rescue IO::WaitReadable
          # STDOUT.syswrite "*** IO::WaitReadable  #{format('%8.5f', Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st)}\n"
          if ssl_socket.wait_readable(0.02) && (time_end > Process.clock_gettime(Process::CLOCK_MONOTONIC))
            retry
          else
            ssl_socket.close if ssl_socket.respond_to?(:close)
            raise OpenSSL::SSL::SSLErrorWaitReadable
          end
        rescue IO::WaitWritable
          # STDOUT.syswrite "*** IO::WaitWritable  #{format('%8.5f', Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st)}\n"
          if ssl_socket.wait_writable(0.02) && (time_end > Process.clock_gettime(Process::CLOCK_MONOTONIC))
            retry
          else
            ssl_socket.close if ssl_socket.respond_to?(:close)
            raise OpenSSL::SSL::SSLErrorWaitWritable
          end
        rescue OpenSSL::SSL::SSLError => e
          raise e
        end
        ssl_socket
      end
    end
  end
end
