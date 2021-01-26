# frozen_string_literal: true

require 'optparse'

module TestPuma
  class ClientsBase

    def initialize
      @thread_loops       = nil
      @clients_per_thread = nil
      @req_per_client     = nil
      @body_kb            = 10
      @dly_app            = nil
      @bind_type          = :tcp

      @ios_to_close = []

      setup_options

      case @bind_type
      when :ssl, :tcp
        @bind_port = ENV.fetch('PORT', 40010).to_i
      when :unix
        @bind_path = "#{Dir.home}/skt.unix"
      when :aunix
        @bind_path = "@skt.aunix"
      else
        exit 1
      end
    end

    def setup_options
      OptionParser.new do |o|
        o.on "-l LOOPS", "create_clients loops/threads" do |arg|
          @thread_loops = arg.to_i
        end

        o.on "-c", "--connections CONNECTIONS", OptionParser::DecimalInteger, "create_clients clients_per_thread" do |arg|
          @clients_per_thread = arg.to_i
        end

        o.on "-r", "--requests REQUESTS", OptionParser::DecimalInteger, "create_clients requests per client" do |arg|
          @req_per_client = arg.to_i
        end

        o.on "-b", "--body_kb BODYKB", OptionParser::DecimalInteger, "create_clients size of response body in kB" do |arg|
          @body_kb = arg.to_i
        end

        o.on "-d", "--dly_app DELAYAPP", Float, "create_clients app response delay" do |arg|
          @dly_app = arg.to_f
        end

        o.on "-s", "--socket SOCKETTYPE", String, "create_clients app response delay" do |arg|
          @bind_type = arg.to_sym
        end

        o.on("-h", "--help", "Prints this help") do
          puts o
          exit
        end
      end.parse! ARGV
    end

    def close_clients
      closed = 0
      @ios_to_close.each do |socket|
        if socket && socket.to_io.is_a?(IO) && !socket.closed?
          begin
            if @bind_type == :ssl
              socket.sysclose
            else
              socket.close
            end
            closed += 1
          rescue Errno::EBADF
          end
        end
      end
      puts "Closed #{closed} clients" unless closed.zero?
    end
  end
end
