## accessing stats

stats can be accessed via
1. `$ pumactl stats` — read more about `pumactl` and the control server [here](https://github.com/puma/puma#controlstatus-server)
2. `Puma.stats` when in single mode
3. `Puma.stats` when in cluster mode (should not be invoked from worker process, right?)


## meaning of stats

* started_at: when puma was started
* phase: which phase of restart the process is in, during [phased restart](https://github.com/puma/puma/blob/master/docs/restart.md)
* workers: ??
* booted_workers: how many workers currently running?
* old_workers: ??
* worker_status: array of hashes of info for each worker (see below)

## meaning of worker stats

* started_at: when the worker was started
* pid: the process id of the worker process
* index: each worker gets a number. if puma is configured to have 3 workers, then this will be 0, 1, or 2
* booted: if it's done booting [?]
* last_checkin: Last time the worker responded to the master process' heartbeat check.
* last_status: a hash of info about the worker's state handling requests
  * backlog: requests that are waiting for an available thread to be available. if this is above 0, you need more capacity [always true?]
  * running: how many threads are running
  * pool_capacity: the number of requests that the server is capable of taking right now. For example if the number is 5 then it means there are 5 threads sitting idle ready to take a request. If one request comes in, then the value would be 4 until it finishes processing. If the minimum threads allowed is zero, this number will still have a maximum value of the maximum threads allowed.
  * max_threads: the maximum number of threads puma is configured to spool up per worker 
  * requests_count: the number of requests this worker has served since starting
