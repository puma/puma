source "https://rubygems.org"

gemspec

gem "rake-compiler"

gem "json", "~> 2.3"
gem "nio4r", "~> 2.0"
gem "minitest", "~> 5.11"
gem "minitest-retry"
gem "minitest-proveit"
gem "minitest-stub-const"
gem "concurrent-ruby", "~> 1.3"

if ENV['PUMA_CI_RACK']&.strip == 'rack2'
  gem "rack"  , "~> 2.2"
  gem "rackup", "~> 1.0"
## Temporarily disable using rack & rackup main branches
#elsif RUBY_PATCHLEVEL == -1
#  gem "rack"  , github: "rack/rack"  , branch: "main"
#  gem "rackup", github: "rack/rackup", branch: "main"
else
  gem "rack"  , "~> 3.2"
  gem "rackup", "~> 2.3"
end

gem "jruby-openssl", :platform => "jruby"

unless ENV['PUMA_NO_RUBOCOP'] || RUBY_PLATFORM.include?('mswin')
  gem "rubocop"
  gem 'rubocop-performance', require: false
end

if RUBY_VERSION >= '3.5' && ::Gem.win_platform?
  gem "fiddle"
end

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.5")
  gem "logger"
end

gem 'm'
gem "localhost", require: false
