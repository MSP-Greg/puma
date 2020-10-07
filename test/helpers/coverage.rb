require 'simplecov'
require 'securerandom'
require 'stringio'

module ResultPrep
  def format!
    orig_out = $stdout
    orig_err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    super
  ensure
    $stdout = orig_out
    $stderr = orig_err
  end
end

::SimpleCov::Result.prepend ResultPrep

if ENV['CI']
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
else
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
end

SimpleCov.command_name ::SecureRandom.uuid

SimpleCov.start do
  pid = Process.pid
  at_exit do
    SimpleCov.result.format! if Process.pid == pid
  end
  add_filter ["/test/", "lib/puma/rack/"]
  print_error_status = false
  enable_for_subprocesses(true) if ::Process.respond_to?(:fork)
end
