# TestPuma Introduction

## Introduction & Purpose

The TestPuma namespace contains several items that make testing and benchmarking Puma easier
to accomplish.

A common issue with software is how much of the API to expose.  Very 'tight' API's may make
testing more difficult, as data/options needed for testing may not be accessible as they
move thru the code.

Hence, many Puma tests involve starting a Server, either 'in process', or in a sub-process (using `IO.popen`).
One or more client requests are then sent.  For tests/benchmarks using many client requests,
sub-process Server instances are used.  They are also used when the Server must be in another
ruby instance, like testing hot restarts, shutdown, etc.

TestPuma supplies methods that allow the following:

1. Simple configuration of Puma servers, whether 'in process' (see `TestPuma::SvrInProc`),
or as a sub-process (see `TestPuma::SvrPOpen`).

2. Create client sockets for requests and inspecting their responses.  Server configuration
also sets variables that determine what type of client sockets are created.  This makes it
easy to share code when testing against several socket types, ie, ssl, tcp, unix, and
abstract unix.  Since tests are often run parallel, ports/paths are unique to Puma/server
instances.

3. Create a stream of client requests to test Puma.  Supply methods so the response times
and errors can be operated on and also output.  This is also usable for benchmarks, providing
that instance variables are set.

Lastly, the TestPuma libraries handle tasks that help with test isolation.  Teardown methods
close all client sockets, make sure the servers are stopped, remove UNIXSocket files, etc.

## TestPuma Classes & Modules (all files in `test/helpers`)

**`TestPuma::SvrInProc`** - Contained in `svr_in_proc.rb`.  Used as a superclass for test
files, starts a `Server` in process.  Sets variables used by the client code.

**`TestPuma::SvrPOpen`** - Contained in `svr_popen.rb`.  Used as a superclass for test
files, contains code to start Puma via `CLI` using `IO.popen`.  Sets variables used by the
client code.

**`TestPuma::SvrBase`** - Contained in `svr_base.rb`.  Superclass for above server classes.
Subclassed from `::Minitest::Test`.

**`TestPuma::SktPrepend`** - Contained in `sockets.rb`.  Module that is prepended into the
TestPuma socket classes.  All methods operate on 'self'.

**`TestPuma::SktSSL`, `TestPuma::SktTCP`, `TestPuma::SktUNIX`** - Contained in `sockets.rb`.
The three sockets classes used by clients.

**`TestPuma::Sockets`** - Contained in `sockets.rb`.  A module that is included in
`TestPuma::SvrInProc` or `TestPuma::SvrPOpen`.  Provides test client socket methods to create
requests and read responses.  Also contains `create_clients`, which creates a stream of
requests.

## Misc Files

Three rackup files are often used.  All are in `test/rackup`.  All responses have the following:

1. 25 headers, each with a value of fifty (50) characters.

2. A delay can be set by passing a `Dly:` header in the request.  Time is in seconds.

3. The body length can be set.  Either use an env variable, `CI_TEST_KB`, or set a `Len:`
header.  Value is in kB, with a default of 10 kB.

4. All bodies have the pid on the first line, "Hello World" on the second, and if the delay
is set, `"Slept #{dly}"` on the third.

**`ci_string.ru`** - returns a body as a string.  'Content-Length' header is set.

**`ci_array.ru`** - returns a body as an array of 1kB strings.  'Content-Length' header is set.

**`ci_chunked.ru`** - returns a body as an array of 1kB strings.  'Content-Length' is not set.

## Benchmarks

Files are in the `benchmarks/local` folder:

**`benchmark_base.rb`** - 

**`benchmark_base.sh`** - 

**`overload_wrk.rb`** - 

**`overload_wrk.sh`** - 

**`puma_info.rb`** - 

