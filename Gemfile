source "https://rubygems.org"

gemspec

gem "rake-compiler", "~> 1.1.1"

gem "json", "~> 2.3"
gem "nio4r", "~> 2.0"
gem "minitest", "~> 5.11"
gem "minitest-retry"
gem "minitest-proveit"
gem "minitest-stub-const"
gem "sd_notify"

gem "rack", (ENV['PUMA_CI_RACK_2'] ? "~> 2.2" : ">= 2.2")

gem "jruby-openssl", :platform => "jruby"

unless ENV['PUMA_NO_RUBOCOP'] || RUBY_PLATFORM.include?('mswin')
  gem "rubocop", "1.12.1"
  gem 'rubocop-performance', require: false
end

if RUBY_VERSION == '2.4.1'
  gem "stopgap_13632", "~> 1.0", :platforms => ["mri", "mingw", "x64_mingw"]
end

gem 'm'
gem "localhost", require: false
