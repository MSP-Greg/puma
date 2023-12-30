# frozen_string_literal: true

require 'socket'
require 'tmpdir'

# This module is included in `TesPuma::ServerBase` and contains methods used
# across the test framework.  It also includes a few class methods related to
# debug logging.

module TestPuma

  DEBUGGING_INFO = Queue.new
  DEBUGGING_PIDS = {}

  GITHUB_ACTIONS  = ENV['GITHUB_ACTIONS'] == 'true'
  PUMA_TEST_DEBUG = ENV['PUMA_TEST_DEBUG'] == 'true'

  AFTER_RUN_OK = [false]

  RE_HOST_TO_IP = /\A\[|\]\z/o

  RESP_SPLIT = "\r\n\r\n"
  LINE_SPLIT = "\r\n"

  HOST4 = begin
    t = Socket.ip_address_list.select(&:ipv4_loopback?).map(&:ip_address)
      .uniq.sort_by(&:length)
    # puts "IPv4 Loopback #{t}"
    str = t.include?('127.0.0.1') ? +'127.0.0.1' : +"#{t.first}"
    str.define_singleton_method(:ip) { self }
    str.freeze
  end

  HOST6 = begin
    t = Socket.ip_address_list.select(&:ipv6_loopback?).map(&:ip_address)
      .uniq.sort_by(&:length)
    # puts "IPv6 Loopback #{t}"
    str = t.include?('::1') ? +'[::1]' : +"[#{t.first}]"
    str.define_singleton_method(:ip) { self.gsub RE_HOST_TO_IP, '' }
    str.freeze
  end

  LOCALHOST = ENV.fetch 'PUMA_CI_DFLT_HOST', 'localhost'

  if ENV['PUMA_CI_DFLT_IP'] =='IPv6'
    HOST     = HOST6
    ALT_HOST = HOST4
  else
    HOST     = HOST4
    ALT_HOST = HOST6
  end

  DARWIN = RUBY_PLATFORM.include? 'darwin'

  TOKEN = "xxyyzz"

  def before_setup
    @files_to_unlink = nil
  end

  def after_teardown
    @files_to_unlink&.each do |path|
      begin
        File&.unlink path
      rescue Errno::ENOENT
      end
    end
  end

  # Returns an available port by using `TCPServer.open(host, 0)`
  def unique_port(host = HOST)
    host = host.gsub RE_HOST_TO_IP, ''
    TCPServer.open(host, 0) { |server| server.connect_address.ip_port }
  end

  alias_method :new_port, :unique_port

  # With some macOS configurations, the following error may be raised when
  # creating a UNIXSocket:
  #
  # too long unix socket path (106 bytes given but 104 bytes max) (ArgumentError)
  #
  PUMA_CI_TMPDIR =
    begin
      if ::Puma::IS_OSX
        # adds subdirectory 'tmp/ci' in repository folder
        dir_temp = File.absolute_path("#{__dir__}/../../tmp")
        Dir.mkdir(dir_temp) unless Dir.exist? dir_temp
        dir_temp += '/ci'
        Dir.mkdir(dir_temp) unless Dir.exist? dir_temp
        dir_temp
      elsif GITHUB_ACTIONS && (rt_dir = ENV['RUNNER_TEMP'])
        # GitHub runners temp may be on a HD, rt_dir is always an SSD
        rt_dir
      else
        Dir.tmpdir()
      end
    end

  UNUSABLE_CHARS = "^,-.0-9A-Z_a-z~"
  private_constant :UNUSABLE_CHARS

  # Dedicated random number/string generator for
  RANDOM = Object.new
  class << RANDOM
    # Maximum random number
    MAX = 36**6 # 2_176_782_336

    # Returns new random string up to 6 characters, all characters match [0-9a-z]
    def next
      rand(MAX).to_s(36)
    end
  end
  RANDOM.freeze
  private_constant :RANDOM

  # Generates a unique file path.  Optionally, writes to the file
  def unique_path(basename = '', dir: PUMA_CI_TMPDIR, contents: nil, io: nil)
    max_try = 10
    n = nil
    if basename.is_a? String
      prefix, suffix = '', basename
    else
      prefix, suffix = basename
    end
    prefix = (String.try_convert(prefix) or
              raise ArgumentError, "unexpected prefix: #{prefix.inspect}")
    prefix = prefix.delete(UNUSABLE_CHARS)
    suffix &&= (String.try_convert(suffix) or
                raise ArgumentError, "unexpected suffix: #{suffix.inspect}")
    suffix &&= suffix.delete(UNUSABLE_CHARS)

    loop do
      # 366235959999.to_s(36) => 4o8vfnb3, eight characters
      # dddhhmmss ms  'ddd' stands for 'day of year'
      t = Time.now.strftime('%j%H%M%S%L').to_i.to_s(36).rjust 8, '0'
      path = "#{prefix}#{t}-#{RANDOM.next}"\
             "#{n ? %[-#{n}] : ''}#{suffix || ''}"
      path = File.join(dir, path)
      unless File.exist? path
        File.write(path, contents, perm: 0600, mode: 'wb') if contents
        (@files_to_unlink ||= []) << path
        return io ? File.open(path) : path
      end
      n ||= 0
      n += 1
      if n > max_try
        raise "cannot generate temporary name using `#{basename}' under `#{dir}'"
      end
    end
  end

  def with_env(env = {})
    original_env = {}
    env.each do |k, v|
      original_env[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    original_env.each do |k, v|
      v.nil? ? ENV.delete(k) : ENV[k] = v
    end
  end

  def kill_and_wait(pid, signal: nil, timeout: 10)
    signal ||= :SIGINT
    signal = :SIGKILL if Puma::IS_WINDOWS
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    wait2_timeout pid, timeout: timeout
  end

  def wait2_timeout(pid, timeout: 10)
    ary = nil
    err_msg = "Waited #{timeout} seconds for Process.wait2"

    th = Thread.new do
      begin
        ary = Process.wait2 pid
      rescue Errno::ECHILD
      end
    end

    unless th.join(timeout)
      Thread.kill th
      raise(Timeout::Error, err_msg)
    end

    ary
  end

  module_function :kill_and_wait, :wait2_timeout

  def self.log_ssl_info(io)
    if ::Puma::HAS_SSL && PUMA_TEST_DEBUG
      require "puma/minissl"

      if PUMA_TEST_DEBUG
        require "openssl" unless Object.const_defined? :OpenSSL
        if Puma::IS_JRUBY
          io.syswrite "\n#{RUBY_DESCRIPTION}\nRUBYOPT: #{ENV['RUBYOPT']}\n" \
            "                         OpenSSL\n" \
            "OPENSSL_LIBRARY_VERSION: #{OpenSSL::OPENSSL_LIBRARY_VERSION}\n" \
            "        OPENSSL_VERSION: #{OpenSSL::OPENSSL_VERSION}\n\n"
        else
          io.syswrite "\n#{RUBY_DESCRIPTION}\nRUBYOPT: #{ENV['RUBYOPT']}\n" \
            "                         Puma::MiniSSL                   Ruby OpenSSL\n" \
            "OPENSSL_LIBRARY_VERSION: #{Puma::MiniSSL::OPENSSL_LIBRARY_VERSION.ljust 32}" \
            "#{OpenSSL::OPENSSL_LIBRARY_VERSION}\n" \
            "        OPENSSL_VERSION: #{Puma::MiniSSL::OPENSSL_VERSION.ljust 32}" \
            "#{OpenSSL::OPENSSL_VERSION}\n\n"
        end
      end
    end
  end

  # Only a problem with JRuby?
  def self.thread_killer
    return unless Puma::IS_JRUBY
    puma_threads = Thread.list.select { |th| th.name&.start_with? 'puma' }

    puma_threads.each do |th|
      th.wakeup if th.alive?
      th.join 1.0
    end
    puma_threads.each do |th|
      Thread.kill th if th.alive?
    end
  end

  def self.handle_defunct
    defunct = {}
    txt = +''
    loop do
      begin
        pid, status = Process.wait2(-1, Process::WNOHANG)
        break unless pid
        defunct[pid] = status unless ::Puma::IS_WINDOWS && status == 0
      rescue Errno::ECHILD
        break
      end
    end

    unless defunct.empty?
      dash = "\u2500"
      txt << (GITHUB_ACTIONS ? "\n\n##[group]Child Processes:\n" :
        "\n\n#{dash * 40} Child Processes:\n")

      txt << format("%5d      Test Process\n", Process.pid)

      # list all children, kill test processes
      defunct.each do |pid, status|
        if (test_name = DEBUGGING_PIDS[pid])
          txt << format("%5d #{status&.exitstatus.to_s.rjust 3}  #{test_name}\n", pid)
          kill_and_wait pid
        else
          txt << format("%5d #{status&.exitstatus.to_s.rjust 3}  Unknown\n", pid)
        end
      end

      # kill unknown processes
      defunct.each do |pid, _|
        unless DEBUGGING_PIDS.key? pid
          kill_and_wait pid
        end
      end

      txt << (GITHUB_ACTIONS ? "::[endgroup]\n\n" : "#{dash * 57}\n\n")
    end

    TestPuma::AFTER_RUN_OK[0] = true
    txt
  end

  def self.debugging_info
    info = ''
    if AFTER_RUN_OK[0] && PUMA_TEST_DEBUG && !DEBUGGING_INFO.empty?
      ary = Array.new(DEBUGGING_INFO.size) { DEBUGGING_INFO.pop }
      ary.sort!
      out = ary.join.strip
      unless out.empty?
        dash = "\u2500"
        wid = GITHUB_ACTIONS ? 88 : 90
        txt = " Debugging Info #{dash * 2}".rjust wid, dash
        if GITHUB_ACTIONS
          info = "\n\n##[group]#{txt}\n#{out}\n#{dash * wid}\n\n::[endgroup]\n\n"
        else
          info = "\n\n#{txt}\n#{out}\n#{dash * wid}\n\n"
        end
      end
    end
    info
  ensure
    DEBUGGING_INFO.close
  end
end
