log_requests
stdout_redirect "t2-stdout"
pidfile "t2-pid"
rackup File.expand_path('../rackup/hello.ru', File.dirname(__FILE__))
