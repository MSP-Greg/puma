source "https://rubygems.org"

gemspec

gem "rdoc"
gem "rake-compiler", "~> 1.1.1"

gem "json", "~> 2.3"
gem "nio4r", "~> 2.0"
gem "minitest", "~> 5.11"
gem "minitest-retry"
gem "minitest-proveit"
gem "minitest-stub-const"
gem "sd_notify"

use_rackup = false
rack_vers =
  case ENV.key?('PUMA_CI_RACK') && ENV['PUMA_CI_RACK'].strip
  when 'rack2'
    '~> 2.2'
  when 'rack1'
    '~> 1.6'
  else
    use_rackup = true
    '>= 2.2'
  end

gem "rack", rack_vers
gem "rackup" if use_rackup

gem "jruby-openssl", :platform => "jruby"

gem "rubocop", "~> 0.64.0"

if %w(2.2.7 2.2.8 2.2.9 2.2.10 2.3.4 2.4.1).include? RUBY_VERSION
  gem "stopgap_13632", "~> 1.0", :platforms => ["mri", "mingw", "x64_mingw"]
end

gem 'm'
gem "localhost", require: false
