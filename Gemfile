source "https://rubygems.org"

gemspec

gem "rake-compiler", "~> 1.1.9"

gem "json", "~> 2.3"
gem "nio4r", "~> 2.0"
gem "minitest", "~> 5.11"
gem "minitest-retry"
gem "minitest-proveit"
gem "minitest-stub-const"

use_rackup = false
rack_vers =
  case ENV['PUMA_CI_RACK']&.strip
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

gem "sqlite3", "~> 1.4"

unless ENV['PUMA_NO_RUBOCOP'] || RUBY_PLATFORM.include?('mswin')
  gem "rubocop"
  gem 'rubocop-performance', require: false
end

if RUBY_VERSION == '2.4.1'
  gem "stopgap_13632", "~> 1.0", :platforms => ["mri", "mingw", "x64_mingw"]
end

gem 'm'
gem "localhost", require: false
