source "https://rubygems.org"

gemspec

gem "rake-compiler"

# Release tooling requires Ruby 3.3+; Puma itself still supports Ruby 3.0.
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
  # Pin the unreleased 0.7.0 APIs until publication.
  gem "ruby-gem-release", "0.7.0", git: "https://github.com/dblock/ruby-gem-release.git",
    ref: "593b161261c504f2ec3dda97b6df4d816cad4ac5", require: false
  gem "commonmarker", "~> 2.10", require: false if RUBY_ENGINE == "ruby" && RUBY_PLATFORM.match?(/linux|darwin/)
end

gem "json", "~> 2.18"
gem "nio4r", "~> 2.7"
gem "minitest", ">= 5.26"
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

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2")
  gem "minitest-mock"
end

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.5")
  gem "logger"
  if ::Gem.win_platform?
    gem "fiddle"
  end
end

gem 'm'
gem "localhost", require: false
