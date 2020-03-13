port ENV['PORT'] if ENV['PORT']

app do |env|
  [200, {}, ["embedded app"]]
end

lowlevel_error_handler do |err|
  [200, {}, ["error page"]]
end

force_shutdown_error_response(
  500,
  {"Content-Type" => "application/json"},
  ["{}"]
)
