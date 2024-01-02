# frozen_string_literal: true
# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require_relative "minitest/verbose"
require "minitest/autorun"
require "minitest/pride"
require "minitest/proveit"
require "minitest/stub_const"

if RUBY_VERSION == '2.4.1'
  begin
    require 'stopgap_13632'
  rescue LoadError
    puts "For test stability, you must install the stopgap_13632 gem."
    exit(1)
  end
end

require "puma"
require "puma/detect"

unless ::Puma::HAS_NATIVE_IO_WAIT
  require "io/wait"
end

require "net/http"
require_relative "helpers/apps"
require_relative "helpers/tmp_path"
require_relative "helpers/test_puma"

require "securerandom"

Thread.abort_on_exception = true

$debugging_hold = false   # needed for TestCLI#test_control_clustered

# used in various ssl test files, see test_puma_server_ssl.rb and
# test_puma_localhost_authority.rb
if Puma::HAS_SSL
  require 'puma/log_writer'
  class SSLLogWriterHelper < ::Puma::LogWriter
    attr_accessor :addr, :cert, :error

    def ssl_error(error, ssl_socket)
      self.error = error
      self.addr = ssl_socket.peeraddr.last rescue "<unknown>"
      self.cert = ssl_socket.peercert
    end
  end
end

# Either takes a string to do a get request against, or a tuple of [URI, HTTP] where
# HTTP is some kind of Net::HTTP request object (POST, HEAD, etc.)
def hit(uris)
  uris.map do |u|
    response =
      if u.kind_of? String
        Net::HTTP.get(URI.parse(u))
      else
        url = URI.parse(u[0])
        Net::HTTP.new(url.host, url.port).start {|h| h.request(u[1]) }
      end

    assert response, "Didn't get a response: #{u}"
    response
  end
end

module UniquePort
  def self.call(host = '127.0.0.1')
    TCPServer.open(host, 0) do |server|
      server.connect_address.ip_port
    end
  end
end

require "timeout"
module TimeoutEveryTestCase
  # our own subclass so we never confuse different timeouts
  class TestTookTooLong < Timeout::Error
  end

  TEST_CASE_TIMEOUT = ENV.fetch("TEST_CASE_TIMEOUT") do
    RUBY_ENGINE == "ruby" ? 45 : 60
  end.to_i

  def run
    with_info_handler do
      time_it do
        capture_exceptions do
          ::Timeout.timeout(TEST_CASE_TIMEOUT, TestTookTooLong) do
            before_setup; setup; after_setup
            self.send self.name
          end
        end

        capture_exceptions do
          ::Timeout.timeout(TEST_CASE_TIMEOUT, TestTookTooLong) do
            Minitest::Test::TEARDOWN_METHODS.each { |hook| self.send hook }
          end
        end
        if respond_to? :clean_tmp_paths
          clean_tmp_paths
        end
      end
    end

    Minitest::Result.from self # per contract
  end
end

Minitest::Test.prepend TimeoutEveryTestCase

if ENV['CI']
  require 'minitest/retry'

  Minitest::Retry.use!

  if ENV['GITHUB_ACTIONS'] == 'true'
    Minitest::Retry.on_failure do |klass, test_name, result|
      TestPuma.retry_on_failure(klass, test_name, result)
    end
  end
end

module TestSkips

  HAS_FORK = ::Process.respond_to? :fork
  UNIX_SKT_EXIST = Object.const_defined?(:UNIXSocket) && !Puma::IS_WINDOWS

  MSG_FORK = "Kernel.fork isn't available on #{RUBY_ENGINE} on #{RUBY_PLATFORM}"
  MSG_UNIX = "UNIXSockets aren't available on the #{RUBY_PLATFORM} platform"
  MSG_AUNIX = "Abstract UNIXSockets aren't available on the #{RUBY_PLATFORM} platform"

  SIGNAL_LIST = Signal.list.keys.map(&:to_sym) - (Puma.windows? ? [:INT, :TERM] : [])

  JRUBY_HEAD = Puma::IS_JRUBY && RUBY_DESCRIPTION.include?('SNAPSHOT')

  DARWIN = RUBY_PLATFORM.include? 'darwin'

  TRUFFLE = RUBY_ENGINE == 'truffleruby'
  TRUFFLE_HEAD = TRUFFLE && RUBY_DESCRIPTION.include?('-dev-')

  # usage: skip_unless_signal_exist? :USR2
  def skip_unless_signal_exist?(sig, bt: caller)
    signal = sig.to_s.sub(/\ASIG/, '').to_sym
    unless SIGNAL_LIST.include? signal
      skip "Signal #{signal} isn't available on the #{RUBY_PLATFORM} platform", bt
    end
  end

  # called with one or more params, like skip_if :jruby, :windows
  # optional suffix kwarg is appended to the skip message
  # optional suffix bt should generally not used
  def skip_if(*engs, suffix: '', bt: caller)
    engs.each do |eng|
      skip_msg = case eng
        when :linux       then "Skipped if Linux#{suffix}"       if Puma::IS_LINUX
        when :darwin      then "Skipped if darwin#{suffix}"      if Puma::IS_OSX
        when :jruby       then "Skipped if JRuby#{suffix}"       if Puma::IS_JRUBY
        when :truffleruby then "Skipped if TruffleRuby#{suffix}" if TRUFFLE
        when :windows     then "Skipped if Windows#{suffix}"     if Puma::IS_WINDOWS
        when :ci          then "Skipped if ENV['CI']#{suffix}"   if ENV['CI']
        when :no_bundler  then "Skipped w/o Bundler#{suffix}"    if !defined?(Bundler)
        when :ssl         then "Skipped if SSL is supported"     if Puma::HAS_SSL
        when :fork        then "Skipped if Kernel.fork exists"   if HAS_FORK
        when :unix        then "Skipped if UNIXSocket exists"    if Puma::HAS_UNIX_SOCKET
        when :aunix       then "Skipped if abstract UNIXSocket"  if Puma.abstract_unix_socket?
        when :rack3       then "Skipped if Rack 3.x"             if Rack.release >= '3'
        when :yjit        then "Skipped if using yjit"           if ENV['RUBYOPT']&.include?('--yjit')
        else false
      end
      skip skip_msg, bt if skip_msg
    end
  end

  # called with only one param
  def skip_unless(eng, bt: caller)
    skip_msg = case eng
      when :linux   then "Skip unless Linux"            unless Puma::IS_LINUX
      when :darwin  then "Skip unless darwin"           unless Puma::IS_OSX
      when :jruby   then "Skip unless JRuby"            unless Puma::IS_JRUBY
      when :windows then "Skip unless Windows"          unless Puma::IS_WINDOWS
      when :mri     then "Skip unless MRI"              unless Puma::IS_MRI
      when :ssl     then "Skip unless SSL is supported" unless Puma::HAS_SSL
      when :fork    then MSG_FORK                       unless HAS_FORK
      when :unix    then MSG_UNIX                       unless Puma::HAS_UNIX_SOCKET
      when :aunix   then MSG_AUNIX                      unless Puma.abstract_unix_socket?
      when :rack3   then "Skipped unless Rack >= 3.x"   unless ::Rack.release >= '3'
      else false
    end
    skip skip_msg, bt if skip_msg
  end
end

Minitest::Test.include TestSkips

module Minitest
  class Test
    include ::TmpPath
    PROJECT_ROOT = File.dirname(__dir__)

    def self.run(reporter, options = {}) # :nodoc:
      prove_it!
      super
    end

    def full_name
      "#{self.class.name}##{name}"
    end
  end
end

# shows skips summary instead of raw list
module AggregatedResults
  def start
    TestPuma.log_ssl_info io
    io << "Minitest Parallel Threads: #{Minitest.parallel_executor.size}\n"
    io << "Test Process.pid: #{Process.pid}\n\n"
    if TestPuma::GITHUB_ACTIONS
      io << "##[group]Test Results:\n"
      %x[echo 'PUMA_TEST_PID=#{Process.pid}' >> $GITHUB_ENV] unless Puma::IS_WINDOWS
    end
    super
  end

  # override, since we write our own failure, error, and skip summary
  def aggregated_results(io)
    io
  end

  # Writes test run timing, which is output after the last test
  def report
    io << "\n::[endgroup]\n" if TestPuma::GITHUB_ACTIONS
    super
  end

  def summary
    # write failures, errors, and skip summaries
    io << TestPuma.test_results_summary("\n#{super}\n\n", results.dup, options)

    # kill threads, only seems to be an issue with JRuby
    TestPuma.thread_killer

    # checks for defunct processes and tries to kill them, generates log data
    defunct = TestPuma.handle_defunct
    io << defunct unless defunct.empty?

    # writes info logged to TestPuma::DEBUGGING_INFO
    debug_info = TestPuma.debugging_info
    io << debug_info unless debug_info.empty?
    ''
  end
end
Minitest::SummaryReporter.prepend AggregatedResults

module TestTempFile
  require "tempfile"
  def tempfile_create(basename, data, mode: File::BINARY)
    fio = Tempfile.create(basename, mode: mode)
    fio.write data
    fio.flush
    fio.rewind
    @ios << fio
    fio
  end
end
Minitest::Test.include TestTempFile
