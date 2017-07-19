source "https://rubygems.org"

gemspec

gem "hoe"
gem "hoe-git"
gem "hoe-ignore"
gem "rdoc"
gem "rake-compiler"

gem "rack", "< 3.0"
gem "minitest", "~> 5.9"

gem "jruby-openssl", :platform => "jruby"

gem "rubocop", "~> 0.49.1"

if %w(2.2.7 2.3.4 2.4.1).include? RUBY_VERSION
  gem "stopgap_13632", "~> 1.0", :platform => "mri"
end
