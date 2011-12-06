state_path "puma.state"
activate_control_app

rackup "test/lobster.ru"
threads 3, 10
