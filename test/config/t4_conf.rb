log_requests

stdout_redirect "t4-stdout"
pidfile "t4-pid"

class CustomLogger
  def initialize(output = STDOUT)
    @output = output
  end

  def write(msg)
    @output.puts 'Custom logging: ' + msg
    @output.flush
  end
end

custom_logger CustomLogger.new(STDOUT)
