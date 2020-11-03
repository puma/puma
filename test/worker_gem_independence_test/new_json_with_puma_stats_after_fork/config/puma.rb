directory File.expand_path("../../current", __dir__)
after_worker_fork { Puma.stats }
