source "https://rubygems.org"

gemspec

gem "rdoc"
gem "rake-compiler", "~> 1.1.1"

gem "json", "~> 2.3"
gem "nio4r", "~> 2.0"
gem "rack", ">= 1.6.13"
gem "minitest", "~> 5.11"
gem "minitest-retry"
gem "minitest-proveit"
gem "minitest-stub-const"
gem "sd_notify"

gem "jruby-openssl", :platform => "jruby"

gem "rubocop", "~> 0.58.0"

if %w(2.2.7 2.2.8 2.2.9 2.2.10 2.3.4 2.4.1).include? RUBY_VERSION
  gem "stopgap_13632", "~> 1.0", :platforms => ["mri", "mingw", "x64_mingw"]
end

gem 'm'
gem "localhost", require: false
