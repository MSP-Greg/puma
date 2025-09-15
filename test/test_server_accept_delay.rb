# frozen_string_literal: true

require_relative "helper"
require "puma/events"
require "puma/server"

class TestServerAcceptDelay < PumaTest
  parallelize_me!

  def setup
    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
  end

  def server_new(wait_for_less_busy_worker = nil, max_threads = nil)
    options = {}
    options[:wait_for_less_busy_worker] = wait_for_less_busy_worker if
      wait_for_less_busy_worker
    options[:max_threads] = max_threads if max_threads

    server = Puma::Server.new(@app, @events, options)

    @wait_for_less_busy_worker = server.options[:wait_for_less_busy_worker]
    @max_threads = server.options[:max_threads]
    @delay_clamp = server.options[:delay_clamp]
    @clamp = @delay_clamp * @max_threads.to_f
    server
  end

  def test_delay_defaults_1
    delay = server_new.delay_calc 1
    calc = @wait_for_less_busy_worker * 1/@clamp
    assert_equal calc, delay
  end

  def test_delay_defaults_2
    delay = server_new.delay_calc @max_threads * 2
    calc = @wait_for_less_busy_worker * @max_threads * 2/@clamp
    assert_equal calc, delay
  end

  def test_delay_defaults_linear
    delay1   = server_new.delay_calc 1
    delay1x  = server_new.delay_calc @max_threads
    delay3x  = server_new.delay_calc @max_threads * 3
    delay20x = server_new.delay_calc @max_threads * 20

    assert_in_delta delay1x/@max_threads, delay1 , 0.000_01
    assert_in_delta delay3x/3           , delay1x, 0.000_01
    assert_in_delta delay20x/20         , delay1x, 0.000_01
  end

  def test_delay_default_clamp_start
    delay = server_new.delay_calc @max_threads * 25
    assert_equal @wait_for_less_busy_worker, delay
  end

  def test_delay_default_clamp
    delay = server_new.delay_calc @max_threads * 50
    assert_equal @wait_for_less_busy_worker, delay
  end
end
