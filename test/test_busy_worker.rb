require_relative 'helpers/svr_in_proc'

class TestBusyWorker < ::TestPuma::SvrInProc
  parallelize_me!

  def setup
    skip_unless :mri # This feature only makes sense on MRI
    super

    @requests = 4             # number of requests
    @requests_count = 0       # number of requests processed
    @requests_running = 0     # current number of requests running
    @requests_max_running = 0 # max number of requests running in parallel

    @replies = {}
    @queue = Queue.new

    @app = ->(env) do
      @queue << 1
      begin
        sleep 0.1
        [200, {}, ["Hello World"]]
      ensure
        @queue << -1
      end
    end
  end

  # Multiple concurrent requests are not processed
  # sequentially as a small delay is introduced
  def test_multiple_requests_waiting_on_less_busy_worker
    run_requests wait_for_less_busy_worker: 0.5

    assert_operator @requests_max_running, :<, @requests, "maximum number of concurrent requests needs to less than #{@requests}"
  end

  # Multiple concurrent requests are processed
  # in parallel as a delay is disabled
  def test_multiple_requests_processing_in_parallel
    run_requests

    assert_equal @requests_max_running, @requests, "maximum number of concurrent requests needs to match"
  end

  private

  def run_requests(**opts)
    opts[:threads] = '5:5'
    start_server opts

    create_clients(@replies, @requests, 1, dly_thread: nil, dly_client: nil).each(&:join)
    get_data

    assert_equal @replies[:success], @requests, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
  end

  # parses the @queue (sequence of 1 & -1) for server request data
  def get_data
    run = 0
    ary = []
    ary << @queue.shift until @queue.empty?

    @requests_count = ary.count(-1)
    @requests_running = ary.inject(0, &:+)                     # Ruby 2.2 no sum

    ary.each { |i|
      run += i
      @requests_max_running = run if run > @requests_max_running
    }
  end
end
