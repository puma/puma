silence_single_worker_warning

workers 1

before_fork do
  require "puma_worker_killer"

  PumaWorkerKiller.config do |config|
    config.ram = 1024 # mb
    config.frequency = 0.3 # seconds
    config.reaper_status_logs = true # Log memory: PumaWorkerKiller: Consuming 54.34765625 mb with master and 1 workers.
  end

  PumaWorkerKiller.start
end
