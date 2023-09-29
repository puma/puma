port ENV.fetch('PORT', 0)

app do |env|
  [200, {}, ["embedded app"]]
end

lowlevel_error_handler do |err|
  [200, {}, ["error page"]]
end
