port ENV['PORT'] if ENV['PORT']

app do |env|
  [200, {}, ["embedded app"]]
end

lowlevel_error_handler do |err|
  [200, {}, ["error page"]]
end
