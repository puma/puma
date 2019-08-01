log_formatter do |str|
  "[#{Process.pid}] [#{Socket.gethostname}] #{Time.now}: #{str}"
end
