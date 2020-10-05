require 'simplecov'
require 'simplecov-lcov'
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
  require 'coveralls'

  SimpleCov::Formatter::LcovFormatter.config do |config|
    config.report_with_single_file = true
    config.lcov_file_name = 'lcov.info'
  end

  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::LcovFormatter,
    Coveralls::SimpleCov::Formatter
  ])
else
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
end

SimpleCov.command_name SecureRandom.uuid

SimpleCov.start do
  pid = Process.pid
  at_exit do
    SimpleCov.result.format! if Process.pid == pid
  end
  add_filter ["/test/", "lib/puma/rack/"]
  print_error_status = false
  enable_for_subprocesses(true) if ::Process.respond_to?(:fork)
end
