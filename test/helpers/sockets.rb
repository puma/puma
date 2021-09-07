# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'io/wait'

module TestPuma

  # @!macro [new] req
  #   @param [String] path request uri path
  #   @param [Float] dly: delay in app when using 'ci' rackups
  #   @param [Int] len: response body size in kB when using 'ci' rackups

  # @!macro [new] tout
  #   @param [Float] timeout: read timeout for socket

  # @!macro [new] ret_skt
  #   @return [SktSSL, SktTCP, SktUNIX] the opened socket


  READ_TIMEOUT = 10

  # This module is prepended into the three socket classes (`SktSSL`, `SktTCP`,
  # `SktUNIX`).
  module SktPrepend

    # @!attribute [r] connection_close
    # Set when a `'Connection: close'` header is included in a response.
    attr_reader :connection_close

    # Sends a get request and returns the body
    # @!macro req
    # @!macro tout
    # @return [String] response body
    def get_body(path = nil, dly: nil, len: nil, timeout: nil)
      fast_write get_req(path, dly: dly, len: len)
      read_body timeout
    end

    # Sends a get request and returns the response
    # @!macro req
    # @!macro tout
    # @return [Array<String, String>] array is [header string, body]
    def get_response(path = nil, dly: nil, len: nil, timeout: nil)
      fast_write get_req(path, dly: dly, len: len)
      read_response timeout
    end

    # Returns the response body
    # @!macro tout
    # @return [String] response body
    def read_body(timeout = nil)
      read_response(timeout).last
    end

    # Reads the response body
    # @!macro tout
    # @return [Array<String, String>] array is [header string, body]
    def read_response(timeout = nil)
      timeout ||= READ_TIMEOUT
      content_length = nil
      chunked = nil
      read_len = 65_536
      response = ''.dup
      t_st = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        begin
          chunk = read_nonblock(read_len, exception: false)
          case chunk
          when String
            unless content_length
              chunked ||= chunk.include? "\r\nTransfer-Encoding: chunked\r\n"
              content_length = (t = chunk[/Content-Length: (\d+)/i , 1]) ? t.to_i : nil
            end

            response << chunk
            hdrs, body = response.split("\r\n\r\n", 2)
            unless body.nil?
              # below could be simplified, but allows for debugging...
              ret =
                if content_length
                  # STDOUT.puts "#{body.bytesize} content length"
                  body.bytesize == content_length
                elsif chunked
                  # STDOUT.puts "#{body.bytesize} chunked"
                  body.end_with? "\r\n0\r\n\r\n"
                elsif !hdrs.empty? && !body.empty?
                  true
                else
                  false
                end
              if ret
                @connection_close = hdrs.include? "\nConnection: close"
                return [hdrs, body]
              end
            end
          when :wait_readable, :wait_writable # :wait_writable for ssl
          when nil
            @connection_close = true
            raise EOFError
          end
          sleep 0.0002
          if timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st
            raise Timeout::Error, 'Client Read Timeout'
          end
        end
      end
    end

    # Sends a get request
    # @!macro req
    def get(path = nil, dly: nil, len: nil)
      fast_write get_req(path, dly: dly, len: len)
    end

    # Writes a string to the socket using `syswrite`.
    # @param [String] str
    # @return [Integer] number of bytes written
    def write(str)
      fast_write str
    end

    # Writes a string to the socket using `syswrite`.
    # @param [String] str
    # @return [self]
    def <<(str)
      fast_write str
      self
    end

    # Writes a string to the socket using `syswrite`.
    # @param [String] str the string to write
    # @return [Integer] the number of bytes written
    def fast_write(str)
      n = 0

      while true
        begin
          n = syswrite str
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK => e
          raise e unless IO.select(nil, [io], nil, 5)
          retry
        rescue Errno::EPIPE, SystemCallError, IOError => e
          raise e
        end

        return n if n == str.bytesize
        str = str.byteslice(n..-1)
      end
    end

    private

    # Returns an HTTP/1.1 GET request string, with 'Dly:' and 'Len:' set for the 'ci-*'
    # rackup files.
    # @!macro req
    # @return [String]
    def get_req(path = nil, dly: nil, len: nil)
      req = "GET /#{path} HTTP/1.1\r\n".dup
      req << "Dly: #{dly}\r\n" if dly
      req << "Len: #{len}\r\n" if len
      req << "\r\n"
    end
  end

  if !Object.const_defined?(:Puma) || Puma.ssl?
    require 'openssl'
    # The SSLSocket class used by the TestPuma framework.  The `SktPrepend` module
    # is prepended.  The socket is opened with parameters set by `bind_type`.
    class SktSSL < ::OpenSSL::SSL::SSLSocket
      prepend SktPrepend
    end
  end

  # The TCPSocket class used by the TestPuma framework.  The `SktPrepend` module
  # is prepended.  The socket is opened with parameters set by `bind_type`.
  class SktTCP < ::TCPSocket
    prepend SktPrepend
  end

  if Object.const_defined? :UNIXSocket
    # The UNIXSocket class used by the TestPuma framework.  The `SktPrepend` module
    # is prepended.  The socket is opened with parameters set by `bind_type`.
    class SktUNIX < ::UNIXSocket
      prepend SktPrepend
    end
  end

  # This module is included in `SvrInProc` and `SvrPOpen`.  The `connect_*` methods
  # create/open a socket and return either the socket or part or all of the response.
  #
  # The `#create_clients` method creates a stream of requests, and collections data
  # into a hash.  The `#replies_info` method generates a string for console output
  # that shows successful request info and also error info.  The `#replies_time_info`
  # method returns both data and a string detailing the request durations.
  # Sample string is:
  #
  #   30000 successful requests (20 loops of 50 clients * 30 requests per client)
  #           10%    20%    40%    50%    60%    80%    90%    95%    97%    99%   100%
  #     mS  10.42  10.50  10.67  10.77  10.87  11.15  11.84  12.94  13.84  15.54  21.54
  #
  # The data is written to the `replies` hash, with the key `:times_summary`.  Example
  # below:
  #
  #   {0.1  => 10.42,
  #    0.2  => 10.5,
  #    0.4  => 10.67,
  #    0.5  => 10.77,
  #    0.6  => 10.87,
  #    0.8  => 11.15,
  #    0.9  => 11.84,
  #    0.95 => 12.94,
  #    0.97 => 13.84,
  #    0.99 => 15.54,
  #    1.0  => 21.54}
  #
  # Note that `#create_clients` is not a replacement for `wrk` or other tools, as
  # it shows different information.  It is not designed to show 'requests per
  # second' (RPS).  RPS is an important metric, but is affected by many things, and
  # can be increased by raising the number of workers and/or threads.
  # `#create_clients` shows the time Puma takes to respond to a request.
  #
  # The constants are included so we don't need to load `puma.rb` or `puma/const.rb`,
  # as this module can be used with benchmarks running in a process separate from Puma.
  #
  module Sockets

    # @!macro [new] connect
    #   @param [Symbol] type: the type of connection, eg, :tcp, :ssl, :aunix, :unix
    #   @param [String, Integer] p: the port or path of the connection

    IS_JRUBY = Object.const_defined? :JRUBY_VERSION

    IS_OSX = RUBY_PLATFORM.include? 'darwin'

    IS_WINDOWS = !!(RUBY_PLATFORM =~ /mswin|ming|cygwin/ ||
      IS_JRUBY && RUBY_DESCRIPTION.include?('mswin'))

    IS_MRI = (RUBY_ENGINE == 'ruby' || RUBY_ENGINE.nil?)

    HOST = TestPuma.const_defined?(:SvrBase) ? SvrBase::HOST :
      ENV.fetch('TEST_PUMA_HOST', '127.0.0.1')

    # OpenSSL::SSL::SSLError is intermittently raised on SSL connect?
    # IOError is intermittent on all platforms (except maybe Windows), seems
    # to be only be raised on SSL connect?
    # macOS sometimes raises Errno::EBADF for socket init error
    #
    OPEN_WRITE_ERRORS = begin
      ary = [Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ENOENT,
        Errno::EPIPE, Errno::EBADF, IOError]
      ary << Errno::ENOTCONN if IS_OSX
      ary << OpenSSL::SSL::SSLError if Object.const_defined?(:OpenSSL)

      ary.freeze
    end

    # Opens a socket.  Normally, the connection info is supplied by calling `bind_type`,
    # but that can be set manually if needed for control sockets, etc.
    # @!macro connect
    # @!macro ret_skt
    #
    def connect(type: nil, p: nil)
      _bind_type = type || @bind_type
      _bind_port = p || @bind_port

      skt =
        case _bind_type
        when :ssl
          ctx = ::OpenSSL::SSL::SSLContext.new.tap { |c|
            c.verify_mode = ::OpenSSL::SSL::VERIFY_NONE
            c.session_cache_mode = ::OpenSSL::SSL::SSLContext::SESSION_CACHE_OFF
          }
          if RUBY_VERSION < '2.3'
            old_verbose, $VERBOSE = $VERBOSE, nil
          end
          temp = SktSSL.new(SktTCP.new(HOST, _bind_port), ctx).tap { |s|
            s.sync_close = true
            s.connect
          }
          $VERBOSE = old_verbose if RUBY_VERSION < '2.3'
          temp
        when :tcp
          SktTCP.new HOST, _bind_port
        when :aunix, :unix
          path = p || @bind_path
          SktUNIX.new path.sub(/\A@/, "\0")
        end
      @connection_close = nil
      @ios_to_close << skt
      skt
    end

    # Creates a get request and returns the socket. Does not read.
    # Socket properties set by `bind_type`.
    # @!macro req
    # @!macro ret_skt
    #
    def connect_get(path = nil, dly: nil, len: nil)
      req = "GET /#{path} HTTP/1.1\r\n".dup
      req << "Dly: #{dly}\r\n" if dly
      req << "Len: #{len}\r\n" if len
      req << "\r\n"
      connect_raw req
    end

    # Creates a get request and returns the response body.
    # Socket properties set by `bind_type`.
    # @!macro req
    # @!macro tout
    # @return [String] response body
    #
    def connect_get_body(path = nil, dly: nil, len: nil, timeout: nil)
      connect_get(path, dly: dly, len: len).read_body timeout
    end

    # Creates a get request and returns the response as an array of two
    # strings, the first is the headers, the second is the body.
    # @!macro req
    # @!macro tout
    # @return [Array<String, String>] response ary
    #
    def connect_get_response(path = nil, dly: nil, len: nil, timeout: nil)
      connect_get(path, dly: dly, len: len).read_response timeout
    end

    # Creates a request and returns the socket. Does not wait for a read.
    # Use to send a raw string, keyword parameters are the same as `connect`.
    # @param str [String] request string
    # @!macro connect
    # @!macro ret_skt
    #
    def connect_raw(str = nil, type: nil, p: nil)
      s = connect type: type, p: p
      s.fast_write str
      s
    end

    # Creates a stream of client sockets.  Simplified code is:
    #
    #    threads.times do |thread|
    #      client_threads << Thread.new do
    #        sleep(dly_thread * thread) if dly_thread
    #        clients_per_thread.times do
    #          req_per_client.times do |req_idx|
    #            # create a client socket if req_idx == 0
    #            # if 'write' error, collect and break
    #            # send a request
    #            # read body
    #            # collect timing or if 'read' errors, collect and break
    #            sleep dly_client if dly_client
    #          end
    #        end
    #      end
    #    end
    #
    # The response body must contain 'Hello World' on a line.  Normally this
    # method should be used with `rackup/ci_array.ru`, `rackup/ci_chunked.ru`,
    # or `rackup/ci_string.ru`.
    #
    # If the client submits several requests, and it receives a `Connection: close`
    # header, it will open a new socket.  If the client has an open or write error,
    # it will stop sending requests.
    #
    # @param [Hash]    replies an empty hash, loaded wityh error and other info
    # @param [Integer] threads number of client threads to create
    # @param [Integer] clients_per_thread number of clients within each thread
    # @param [Integer] req_per_client: number of requests per client
    # @param [Float]   dly_thread: delay added to each thread before a client is created
    # @param [Float]   dly_client: delay between clients
    # @param [Float]   dly_app: delay passed to rack app
    # @param [Integer] body_kb: size of repsonse body in kB
    # @param [Boolean] keep_alive: whether to close connection after each request
    # @param [Integer] resp_timeout: timeout for response read
    #
    # rubocop:disable Metrics/ParameterLists
    def create_clients(replies, threads, clients_per_thread,
      req_per_client: 1, dly_thread: 0.0005, dly_client: 0.0005, dly_app: nil,
      body_kb: 10, keep_alive: true, resp_timeout: READ_TIMEOUT)

      dly_thread ||= 0.0005
      dly_client ||= 0.0005

      # set all the replies keys
      %i[refused_write refused reset restart restart_count
        success timeout bad_response].each { |k| replies[k] = 0 }

      replies[:pids]  = Hash.new 0
      replies[:pids_first] = Hash.new
      replies[:refused_errs_write] = Hash.new 0
      replies[:refused_errs_read]  = Hash.new 0
      replies[:times]  = []

      use_reqs = false
      if req_per_client > 1
        replies[:reqs_good_wr] = Array.new req_per_client, 0
        replies[:reqs_good_rd] = Array.new req_per_client, 0
        use_reqs = true
      end

      client_threads = []
      refused_errors =  read_refused_errors

      mutex_w     = Mutex.new
      mutex_r_ok  = Mutex.new
      mutex_r_bad = Mutex.new

      id_fmt = "%3d %3d %3d"

      reopen_from_eof = false

      threads.times do |thread|
        client_threads << Thread.new do
          sleep(dly_thread * thread) if dly_thread
          clients_per_thread.times do |client_idx|
            socket = nil
            open_write_err = false
            req_per_client.times do |req_idx|
              id = format id_fmt, thread, client_idx, req_idx
              time_st = Process.clock_gettime Process::CLOCK_MONOTONIC
              begin
                if req_idx.zero?
                  socket = connect_get dly: dly_app, len: body_kb
                elsif socket.to_io.closed?
                  # STDOUT.syswrite "#{id} closed?\n"
                  socket = connect_get dly: dly_app, len: body_kb
                elsif socket.connection_close
                  # STDOUT.syswrite "#{id} socket.connection_close\n"
                  socket.close
                  sleep 0.0001
                  socket = connect_get dly: dly_app, len: body_kb
                else
                  # STDOUT.syswrite "#{id} socket.get\n"
                  socket.get dly: dly_app, len: body_kb
                end
                replies[:reqs_good_wr][req_idx] += 1 if use_reqs && !reopen_from_eof
                reopen_from_eof = false
              rescue *OPEN_WRITE_ERRORS => e
                STDOUT.syswrite "#{id} write/open error\n#{e.class} #{e.message}\n"
                # unix Errno::ENOENT, darwin - Errno::ECONNRESET
                mutex_w.synchronize {
                  replies[:refused_errs_write][e.class.to_s] += 1
                  replies[:refused_write] += 1
                }
                open_write_err = true if req_per_client > 1
              rescue => e
                STDOUT.syswrite "#{id} uncaught write/open error\n#{e.class} #{e.message}\n"
              else
                begin
                  body = socket.read_body resp_timeout
                  time_end = Process.clock_gettime Process::CLOCK_MONOTONIC
                  if body =~ /^Hello World$/
                    mutex_r_ok.synchronize {
                      body_pid = body[/\A\d+/].to_i
                      replies[:success] += 1
                      replies[:pids][body_pid] += 1
                      replies[:times] << 1000 * (time_end - time_st)
                      unless replies[:pids_first].key? body_pid
                        replies[:pids_first][body_pid] = replies[:success]
                      end
                      if replies[:phase0_pids]
                        replies[:restart] += 1 unless replies[:phase0_pids].include?(body_pid)
                      else
                        replies[:restart] += 1 if replies[:restart_count] > 0
                      end
                      replies[:reqs_good_rd][req_idx] += 1 if use_reqs
                    }
                  else
                    mutex_r_bad.synchronize { replies[:bad_response] += 1 }
                  end
                rescue Errno::ECONNRESET
                  # connection was accepted but then closed
                  # client would see an empty response
                  mutex_r_bad.synchronize { replies[:reset] += 1 }
                rescue EOFError
                  # assume EOFError is raised when server closed connection?
                  if socket.connection_close
                    # STDOUT.syswrite "#{id} EOF\n"
                    reopen_from_eof = true
                    redo
                  end
                rescue *refused_errors, IOError => e
                  if e.is_a?(IOError) && Thread.current.respond_to?(:purge_interrupt_queue)
                    Thread.current.purge_interrupt_queue
                  end
                  mutex_r_bad.synchronize {
                    replies[:refused_errs_read][e.class.to_s] += 1
                    replies[:refused] += 1
                  }
                rescue ::Timeout::Error
                  mutex_r_bad.synchronize { replies[:timeout] += 1 }
                end
              ensure
                if dly_client && !reopen_from_eof
                  sleep dly_client
                end
                # SSLSocket is not an IO
                if !keep_alive && (req_idx + 1 == req_per_client) &&
                    socket && socket.to_io.is_a?(IO) && !socket.closed?
                  begin
                    if @bind_type == :ssl
                      socket.sysclose
                    else
                      socket.close
                    end
                  rescue Errno::EBADF
                  end
                end
              end
              break if open_write_err
            end # req_per_client.times
          end   # clients_per_thread.times
        end     # Thread.new block
      end       # threads.times
      client_threads
    end

    # Formats data in the replies hash, showing info about successful requests
    # and also requests that aren't successful.  Errors are divided as to whether
    # they are write or read errors.
    # @param [Hash] replies the hash supplied to `create_clients`
    # @return [String] string of info, formatted with ANSI color codes
    #
    def replies_info(replies)
      colors = {
        red:     "\e[31;1m",
        green:   "\e[32;1m",
        yellow:  "\e[33;1m",
        blue:    "\e[34;1m",
        magenta: "\e[35;1m",
        cyan:    "\e[36;1m"
      }
      reset = "\e[0m"

      msg = ''.dup

      c = -> (str, key, clr) {
        t = replies.fetch(key,0)
        unless t.zero?
          msg << "#{colors[clr]}   %4d #{str}#{reset}\n" % t
        end
      }

      c.call('read bad response', :bad_response , :red)
      c.call('read refused*'    , :refused      , :red)
      c.call('read reset'       , :reset        , :red)
      c.call('read timeout'     , :timeout      , :red)
      c.call('write refused*'   , :refused_write, :yellow)
      c.call('success'          , :success      , :green)

      if replies[:restart_count] > 0
        msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
        msg << "   %4d restart count\n" % replies[:restart_count]
        if replies[:pids].keys.length > 1
          pid_idx = replies[:pids_first].to_a.sort_by { |a| -a[1] }
          msg << "   %4d response pids\n" % replies[:pids].keys.length
          msg << "   %4d index of first request in last 'pid'\n" % pid_idx.first[1]
        end
      end

      unless replies[:refused_errs_write].empty?
        msg << '        write refused errors - '
        msg << replies[:refused_errs_write].map { |k,v|
          format "%2d %s", v, k }.join(', ')
        msg << "\n"
      end

      unless replies[:refused_errs_read].empty?
        msg << '        read refused errors - '
        msg << replies[:refused_errs_read].map { |k,v|
          format "%2d %s", v, k }.join(', ')
        msg << "\n"
      end

      if replies[:reqs_good_wr]
        msg << "\nRequests by Number\n       Total"
        replies[:reqs_good_wr].length.times { |idx| msg << " \u2500\u2500 #{idx + 1}".rjust(6) }
        msg << "\nwrite   %4d" % replies[:reqs_good_wr].reduce(:+)
        replies[:reqs_good_wr].each { |i| msg << "  %4d" % i }
        msg << "\n read   %4d" % replies[:reqs_good_rd].reduce(:+)
        replies[:reqs_good_rd].each { |i| msg << "  %4d" % i }
        msg << "\n\n"
      end
      msg
    end

    # Generates the request/response time distribution data and string.  Loads
    # data into `replies[:times_summary]` as a hash, with keys of the percentile,
    # values are the time.
    # @param [Hash] replies the hash supplied to `create_clients`
    # @param [Integer] threads same as `create_clients` parameter
    # @param [Integer] clients_per_thread same as `create_clients` parameter
    # @param [Integer] req_per_client same as `create_clients` keyword
    # @return [String] formatted string of data
    #
    def replies_time_info(replies, threads, clients_per_thread, req_per_client = 1)
      time_ary = replies[:times]
      times_summary = {}
      good_requests  = time_ary.length
      total_requests = threads * clients_per_thread * req_per_client

      rpc = req_per_client == 1 ? '1 request per client' :
        "#{req_per_client} requests per client"

      str = "(#{threads} loops of #{clients_per_thread} clients * #{rpc})"

      ret = ''.dup

      if total_requests == good_requests
        ret << "#{good_requests} successful requests #{str}\n"
      else
        ret << "#{good_requests} successful requests #{str}, BAD REQUESTS #{total_requests - good_requests}\n"
      end

      return "#{ret}\nNeed at least 20 good requests for timing, only have #{good_requests}" if good_requests < 20

      idxs = []
      fmt_vals = '%2s'.dup
      hdr = '     '.dup
      v = ['  mS']

      time_ary.sort!

      time_max = time_ary.last

      digits = 3 - Math.log10(time_max).to_i

      percentile = [0.1, 0.2, 0.4, 0.5, 0.6, 0.8, 0.9, 0.95, 0.97, 0.99, 1.00]

      percentile.each { |n|
        idxs << [(good_requests * n).ceil, good_requests - 1].min

        fmt_vals << (digits < 0 ? "  %5d" : "  %5.#{digits}f")

        hdr << format('  %5s', "#{(100*n).to_i}% ")
      }
      hdr << "\n"

      idxs.pop # don't average the last percentile, 1.00
      idxs.each { |i| v << ((time_ary[i] + time_ary[i-1])/2).round(digits) }
      v << time_max.round(digits)

      percentile.each_with_index { |n, i| times_summary[n] = v[i+1] }

      replies[:times_summary] = times_summary
      ret << "#{hdr}#{format fmt_vals, *v}\n"
    end

    # Defines correct 'refused' errors based on OS and socket type
    # @return [Array<Exception>] Errors classifies as 'refused'
    def read_refused_errors
      if @bind_type == :unix
        ary = IS_OSX ? [Errno::EBADF, Errno::ENOENT, Errno::EPIPE] :
          [Errno::EBADF, Errno::ENOENT]
      else
        ary = IS_OSX ? [Errno::EBADF, Errno::ECONNREFUSED, Errno::EPIPE, EOFError] :
          [Errno::EBADF, Errno::ECONNREFUSED]  # intermittent Errno::EBADF with ssl?
      end
      ary << Errno::ECONNABORTED if IS_WINDOWS
      ary.freeze
    end
  end
end
