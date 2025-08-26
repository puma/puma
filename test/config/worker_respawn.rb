worker_shutdown_timeout 2
# Workers may be respawned with either :TERM or phased restart (:USR1),
# preloading is not compatible with the latter.
preload_app! false
