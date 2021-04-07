## Request and Response Metrics - Response Size, Requests per Second, Client Response Time

Files included in Puma allow benchmarking request/response time or 'requests per seconds'.  This explains some tests that can be done with varied body size, along with chunked and string bodies.

Two rackup files are included that allow changes to the response from test scripts. They are `test/rackup/ci_string.ru` and `test/rackup/ci_chunked.ru`.  Both include 25 headers that total approx 1.6kB.  Their bodies can be varied in 1kB increments.  Both bodies start with the PID of the worker/process on the first line, the next line is 'Hello World'.  `ci_string.ru` adds another line if a 'DLY' header is set in the request.

After that, both files allow the additional body string to be set by either `ENV['CI_TEST_KB']` or a 'LEN' request header.  The value adds 1KB increments.  `ci_string.ru` adds the bytes to the single body string, `ci_chunked.ru` uses 'LEN' for the enumeration counter that returns a 1kB string for each loop.

Two script are provided, both can be set to test tcp, ssl, or unix sockets (no unix sockets with wrk):

1. `benchmarks/wrk/chunked_string_wrk.sh` - this script starts Puma using `ci_chunked.ru`, then runs three set of wrk measurements using 1kB, 10kB, and 100kb bodies.  It then stops Puma, starts another instance using `ci_string.ru`, and runs the same measurements.  Both allow setting the Puma server worker and thread arguments.  Each wrk run is set for 20 seconds.  An example for use on a quad core system and an OS that supports `fork` is:
```
benchmarks/wrk/chunked_string_wrk.sh -s tcp -t5:5 -w2
```

2. `benchmarks/local/chunked_string_times.sh` - this script send a predetermined number of client sockets to the server, and summarized the time from client write to the client receiving all of the response body.  It makes use of `test/helpers/sockets.rb`, see below for more info on that.  It performs a similar set of tests as the above wrk script.  An example for use on a quad core system and an OS that supports `fork` is the following, generating 2,000 requests:
```
benchmarks/local/chunked_string_times.sh -l10 -c100 -r10 -s tcp -t5:5 -w2
```

## `test/helpers/sockets.rb`

`test/helpers/create_clients` is a CI test helper file, designed to make it simple to set up client connections to Puma.  It works with two other files that create Puma servers, using either IO.popen or an in-process `Puma::Server`.   Some of the code is used to create individual clients.  The main method used in `chunked_string_times.sh` is the `create_clients` method, which creates a large number of client connections and reports timing and error information.  Simplified code for it is as follows:

```ruby
client_threads = []

threads.times do |thread|
  client_threads << Thread.new do
    < adjustable delay >
    clients_per_thread.times do
      req_per_client.times do |req_idx|
        begin
          < create socket > if req_idx.zero?
          < socket write request >
        rescue # multiple
          < collect open/write error data >
        end
        begin
          < socket read response >
          < log timing >
        rescue # multiple
          < collect read error data >
        end
        < adjustable delay >
      end
    end
  end
end

< optional server action - restart, shutdown >

client_threads.each(&:join)
```

## General (~ off topic)

`create_clients` can generate enough clients to see 10,000 requests per second in a two worker server (using a response body of 10kB or less).  One can also set the counts high enough to check memory leaks, etc.

Note that there is some 'warm-up' time, so it's best to generate enough connections for the run to last at least one second.  Normally, increasing the 'clients per thread' (or `-c`) is best.

On a good day (uninterrupted), good, experienced coders can identify race, deadlock, threading, and other issues by inspection.  On bad days, having a test/benchmark system that can generate a high volume of client requests is helpful.  `sockets.rb`, along with its companion server files, makes it easy to reconfigure bind protocols, puma server/cli setup, client request setup, etc.