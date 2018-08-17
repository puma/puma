pidfile "t4-pid"
bind 'tcp://0.0.0.0:10104'
rackup File.expand_path('../rackup/hello-logs.ru', File.dirname(__FILE__))
reopen_logs
stdout_redirect "t4-stdout", "t4-stderr", true
daemonize
workers 1
