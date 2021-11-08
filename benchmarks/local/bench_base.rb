# frozen_string_literal: true

require 'optparse'

module TestPuma

  HOST4 = ENV.fetch('PUMA_TEST_HOST4', '127.0.0.1')
  HOST6 = ENV.fetch('PUMA_TEST_HOST6', '::1')
  PORT  = ENV.fetch('PUMA_TEST_PORT', 40001).to_i

  class BenchBase
    # We're running under GitHub Actions
    IS_GHA = ENV['GITHUB_ACTIONS'] == 'true'

    WRK_PERCENTILE = [0.50, 0.75, 0.9, 0.99, 1.0].freeze

    SIZES = [1, 10, 100, 256, 512, 1024, 2048, 2050].freeze

    HDR_BODY_CONF = "Body-Conf: "

    TYPES = [[:a, 'array'].freeze, [:c, 'chunk'].freeze,
      [:s, 'string'].freeze, [:i, 'io'].freeze].freeze

    def initialize
      sleep 5 # wait for server to boot

      @thread_loops       = nil
      @clients_per_thread = nil
      @req_per_client     = nil
      @body_conf          = ''
      @dly_app            = nil
      @bind_type          = :tcp

      @ios_to_close = []

      setup_options

      unless File.exist? @state_file
        puts "can't fined state file '#{@state_file}'"
        exit 1
      end

      mstr_pid = File.binread(@state_file)[/^pid: +(\d+)/, 1].to_i
      begin
        Process.kill 0, mstr_pid
      rescue Errno::ESRCH
        puts 'Puma server stopped?'
        exit 1
      rescue Errno::EPERM
      end

      case @bind_type
      when :ssl, :ssl4, :tcp, :tcp4
        @bind_host = HOST4
        @bind_port = PORT
      when :ssl6, :tcp6
        @bind_host = HOST6
        @bind_port = PORT
      when :unix
        @bind_path = 'tmp/benchmark_skt.unix'
      when :aunix
        @bind_path = '@benchmark_skt.aunix'
      else
        exit 1
      end
    end

    def setup_options
      OptionParser.new do |o|
        o.on "-l", "--loops LOOPS", OptionParser::DecimalInteger, "create_clients: loops/threads" do |arg|
          @thread_loops = arg.to_i
        end

        o.on "-c", "--connections CONNECTIONS", OptionParser::DecimalInteger, "create_clients: clients_per_thread" do |arg|
          @clients_per_thread = arg.to_i
        end

        o.on "-r", "--requests REQUESTS", OptionParser::DecimalInteger, "create_clients: requests per client" do |arg|
          @req_per_client = arg.to_i
        end

        o.on "-b", "--body_conf BODY_CONF", String, "CI RackUp: size of response body in kB" do |arg|
          @body_conf = arg
        end

        o.on "-d", "--dly_app DELAYAPP", Float, "CI RackUp: app response delay" do |arg|
          @dly_app = arg.to_f
        end

        o.on "-s", "--socket SOCKETTYPE", String, "Bind type: tcp, ssl, tcp6, ssl6, unix, aunix" do |arg|
          @bind_type = arg.to_sym
        end

        o.on "-S", "--state STATEFILE", String, "Puma Server: state file" do |arg|
          @state_file = arg
        end

        o.on "-t", "--threads THREADS", String, "Puma Server: threads" do |arg|
          @threads = arg
        end

        o.on "-w", "--workers WORKERS", OptionParser::DecimalInteger, "Puma Server: workers" do |arg|
          @workers = arg.to_i
        end

        o.on "-T", "--time TIME", OptionParser::DecimalInteger, "wrk: duration" do |arg|
          @wrk_time = arg.to_i
        end

        o.on "-W", "--wrk_bind WRK_STR", String, "wrk: bind string" do |arg|
          @wrk_bind_str = arg
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

    def run_wrk_parse(cmd, log: false)
      STDOUT.syswrite cmd.ljust 55

      wrk_output = %x[#{cmd}]
      if log
        puts '', wrk_output, ''
      end

      wrk_data = "#{wrk_output[/\A.+ connections/m]}\n#{wrk_output[/  Thread Stats.+\z/m]}"

      ary = wrk_data[/^ +\d+ +requests.+/].strip.split ' '

      fmt = " | %6s %s %s %7s %8s %s\n"

      STDOUT.syswrite format(fmt, *ary)

      hsh = {}

      hsh[:rps]      = wrk_data[/^Requests\/sec: +([\d.]+)/, 1].to_f.round
      hsh[:requests] = wrk_data[/^ +(\d+) +requests/, 1].to_i
      if (t = wrk_data[/^ +Socket errors: +(.+)/, 1])
        hsh[:errors] = t
      end

      read = wrk_data[/ +([\d.]+)(GB|KB|MB) +read$/, 1].to_f
      unit = wrk_data[/ +[\d.]+(GB|KB|MB) +read$/, 1]

      mult =
        case unit
        when 'KB' then 1_024
        when 'MB' then 1_024**2
        when 'GB' then 1_024**3
        end

      hsh[:read] = (mult * read).round

      if hsh[:errors]
        t = hsh[:errors]
        hsh[:errors] = t.sub('connect ', 'c').sub('read ', 'r')
          .sub('write ', 'w').sub('timeout ', 't')
      end

      t_re = ' +([\d.ums]+)'

      latency =
         wrk_data.match(/^ +50%#{t_re}\s+75%#{t_re}\s+90%#{t_re}\s+99%#{t_re}/).captures
      # add up max time
      latency.push wrk_data[/^ +Latency.+/].split(' ')[-2]

      hsh[:times] = WRK_PERCENTILE.zip(latency.map do |t|
        if t.end_with?('ms')
          t.to_f
        elsif t.end_with?('us')
          t.to_f/1000
        elsif t.end_with?('s')
          t.to_f * 1000
        else
          0
        end
      end).to_h
      hsh
    end

    def env_log
      puts "#{ENV['PUMA_BENCH_CMD']} #{ENV['PUMA_BENCH_ARGS']}"
      puts @workers ?
        "Server cluster mode -w#{@workers} -t#{@threads}, bind: #{@bind_type}" :
        "Server single mode -t#{@threads}, bind: #{@bind_type}"

      branch = %x[git branch][/^\* (.*)/, 1]
      if branch
        puts "Puma repo branch #{branch.strip}", RUBY_DESCRIPTION, ''
      else
        const = File.read File.expand_path('../../lib/puma/const.rb', __dir__)
        puma_version = const[/^ +PUMA_VERSION[^'"]+['"]([^\s'"]+)/, 1]
        puts "Puma version #{puma_version}", RUBY_DESCRIPTION, ''
      end
    end

    def parse_stats
      stats = {}

      obj = @puma_info.run 'stats'

      worker_status = obj[:worker_status]

      worker_status.each do |w|
        pid = w[:pid]
        req_cnt = w[:last_status][:requests_count]
        id = format 'worker-%01d-%02d', w[:phase], w[:index]
        hsh = {
          pid: pid,
          requests: req_cnt - @worker_req_ttl[pid],
          backlog: w[:last_status][:backlog]
        }
        @pids[pid] = id
        @worker_req_ttl[pid] = req_cnt
        stats[id] = hsh
      end

      stats
    end

    def parse_smem
      @puma_info.run 'gc'
      sleep 1

      hsh_smem = Hash.new []
      pids = @pids.keys

      smem_info = %x[smem -c 'pid rss pss uss command']

      smem_info.lines.each do |l|
        ary = l.strip.split ' ', 5
        if pids.include? ary[0].to_i
          hsh_smem[@pids[ary[0].to_i]] = {
            pid: ary[0].to_i,
            rss: ary[1].to_i,
            pss: ary[2].to_i,
            uss: ary[3].to_i
          }
        end
      end
      hsh_smem.sort.to_h
    end

    def create_io_files
      require 'tmpdir'
      fn_format = "#{Dir.tmpdir}/body_io_%04d.txt"
      str = ("── Puma Hello World! ── " * 31) + "── Puma Hello World! ──\n"  # 1 KB
      SIZES.each do |len|
        suf = format "%04d", len
        fn = format fn_format, len
        unless File.exist? fn
          body = "Hello World\n#{str}".byteslice(0,1023) + "\n" + (str * (len-1))
          File.write fn, body
        end
      end
    end
  end
end
