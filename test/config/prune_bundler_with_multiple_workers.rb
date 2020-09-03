require 'bundler/setup'
Bundler.setup

prune_bundler true

workers 2

app do |env|
  [200, {}, ["embedded app"]]
end

lowlevel_error_handler do |err|
  [200, {}, ["error page"]]
end
