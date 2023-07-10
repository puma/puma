# Large file upload demo

This is a simple app to demonstrate memory used by Puma for large file uploads and
compare it to proposed changes in PR https://github.com/puma/puma/pull/3062

### Steps to test memory improvements in https://github.com/puma/puma/pull/3062

- Run the app with puma_worker_killer: `bundle exec puma -p 9090 --config puma.rb`
- Make a POST request with curl: `curl --form "data=@some_large_file.mp4" --limit-rate 10M http://localhost:9090/`
- Puma will log memory usage in the console

Below is example of the results uploading a 115MB video.

### Puma 6.0.2

```
[11820] Puma starting in cluster mode...
[11820] * Puma version: 6.0.2 (ruby 3.2.0-p0) ("Sunflower")
[11820] *  Min threads: 0
[11820] *  Max threads: 5
[11820] *  Environment: development
[11820] *   Master PID: 11820
[11820] *      Workers: 1
[11820] *     Restarts: (✔) hot (✔) phased
[11820] * Listening on http://0.0.0.0:3000
[11820] Use Ctrl-C to stop
[11820] - Worker 0 (PID: 11949) booted in 0.06s, phase: 0
[11820] PumaWorkerKiller: Consuming 70.984375 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 70.984375 mb with master and 1 workers.

...curl request made - memory increases as file is received

[11820] PumaWorkerKiller: Consuming 72.796875 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 75.921875 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 78.953125 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 82.15625 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 85.265625 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 88.046875 mb with master and 1 workers.

...(clipped out lines) memory keeps increasing while request is received

[11820] PumaWorkerKiller: Consuming 121.53125 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 122.75 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 125.40625 mb with master and 1 workers.

...request handed off from Puma to Rack/Sinatra

[11820] PumaWorkerKiller: Consuming 220.6875 mb with master and 1 workers.
127.0.0.1 - - [26/Jan/2023:20:09:56 -0500] "POST /upload HTTP/1.1" 200 162 0.0553
[11820] PumaWorkerKiller: Consuming 228.96875 mb with master and 1 workers.
[11820] PumaWorkerKiller: Consuming 228.96875 mb with master and 1 workers.
```

### With PR https://github.com/puma/puma/pull/3062

```
[20815] Puma starting in cluster mode...
[20815] * Puma version: 6.0.2 (ruby 3.2.0-p0) ("Sunflower")
[20815] *  Min threads: 0
[20815] *  Max threads: 5
[20815] *  Environment: development
[20815] *   Master PID: 20815
[20815] *      Workers: 1
[20815] *     Restarts: (✔) hot (✔) phased
[20815] * Listening on http://0.0.0.0:3000
[20815] Use Ctrl-C to stop
[20815] - Worker 0 (PID: 20944) booted in 0.1s, phase: 0
[20815] PumaWorkerKiller: Consuming 73.25 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.25 mb with master and 1 workers.

...curl request made - memory stays level as file is received

[20815] PumaWorkerKiller: Consuming 73.28125 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.296875 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.34375 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.359375 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.359375 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.359375 mb with master and 1 workers.

...(clipped out lines) memory continues to stay level

[20815] PumaWorkerKiller: Consuming 73.703125 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.703125 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 73.703125 mb with master and 1 workers.

...request handed off from Puma to Rack/Sinatra

[20815] PumaWorkerKiller: Consuming 181.96875 mb with master and 1 workers.
127.0.0.1 - - [26/Jan/2023:20:27:16 -0500] "POST /upload HTTP/1.1" 200 162 0.0585
[20815] PumaWorkerKiller: Consuming 183.78125 mb with master and 1 workers.
[20815] PumaWorkerKiller: Consuming 183.78125 mb with master and 1 workers.
```
