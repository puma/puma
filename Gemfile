source "https://rubygems.org"

gemspec

gem "rdoc"
gem "rake-compiler"

gem "rack", "< 3.0"
gem "minitest", "~> 5.9"
gem "minitest-retry"

gem "jruby-openssl", :platform => "jruby"

gem "rubocop", "~> 0.49.1"

if %w(2.2.8 2.3.4 2.4.1).include? RUBY_VERSION
  gem "stopgap_13632", "~> 1.0", :platforms => ["mri", "mingw", "x64_mingw"]
end
