stdout_redirect "t2-stdout"
pidfile "t2-pid"
bind "tcp://0.0.0.0:10103"
rackup File.expand_path('../hello.ru', File.dirname(__FILE__))
daemonize
