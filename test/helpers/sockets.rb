# frozen_string_literal: true

require 'socket'
require 'timeout'

module TestPuma

  READ_TIMEOUT = 10

  module SktPrepend
    def get_body(path = nil, dly: nil, len: nil, timeout: 10)
      fast_write get_req(path, dly: dly, len: len)
      read_body timeout
    end

    def get_response(path = nil, dly: nil, len: nil, timeout: 10)
      fast_write get_req(path, dly: dly, len: len)
      read_response timeout
    end

    def read_body(timeout = 10)
      response = read_response timeout
      response.split("\r\n\r\n").last
    end

    def read_response(timeout = 10)
      content_length = nil
      response = ''.dup
      t_st = Time.now
      loop do
        begin
          chunk = read_nonblock(16_384, exception: true)
          if chunk.is_a? String
            response << chunk
            if (content_length ||= (t = response[/Content-Length: (\d+)/i , 1]) ? t.to_i : nil)
              return response if response.split("\r\n\r\n", 2).last.bytesize == content_length
            else
              return response if response.split("\r\n\r\n", 2).length == 2
            end
          end
        rescue EOFError # for debugging, intermittent
          raise EOFError
        rescue ::IO::WaitReadable
        ensure
          sleep 0.0002
          if timeout < Time.now - t_st
            raise ::Timeout::Error, 'Client Read Timeout'
          end
        end
      end
    end

    def get(path = nil, dly: nil, len: nil)
      fast_write get_req(path, dly: dly, len: len)
    end

    def write(str)
      fast_write str
    end

    def <<(str)
      fast_write str
    end

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

        return if n == str.bytesize
        str = str.byteslice(n..-1)
      end
    end

    private

    def get_req(path = nil, dly: nil, len: nil)
      req = "GET /#{path} HTTP/1.1\r\n".dup
      req << "Dly: #{dly}\r\n" if dly
      req << "Len: #{len}\r\n" if len
      req << "\r\n"
    end
  end

  class SktTCP < ::TCPSocket
    prepend SktPrepend
  end

  if Object.const_defined? :UNIXSocket
    class SktUnix < ::UNIXSocket
      prepend SktPrepend
    end
  end

  if !Object.const_defined?(:Puma) || ::Puma.ssl?
    require 'openssl'
    class SktSSL < ::OpenSSL::SSL::SSLSocket
      prepend SktPrepend
    end
  end

  module Sockets

    IS_JRUBY = Object.const_defined? :JRUBY_VERSION

    IS_OSX = RUBY_PLATFORM.include? 'darwin'

    IS_WINDOWS = !!(RUBY_PLATFORM =~ /mswin|ming|cygwin/ ||
      IS_JRUBY && RUBY_DESCRIPTION.include?('mswin'))

    IS_MRI = (RUBY_ENGINE == 'ruby' || RUBY_ENGINE.nil?)

    HOST = TestPuma.const_defined?(:SvrBase) ? SvrBase::HOST : '127.0.0.1'

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


    def fast_connect_get_body(path = nil, dly: nil, len: nil, timeout: READ_TIMEOUT)
      fast_connect_get(path, dly: dly, len: len).read_body timeout
    end

    def fast_connect_get_response(path = nil, dly: nil, len: nil, timeout: READ_TIMEOUT)
      fast_connect_get(path, dly: dly, len: len).read_response timeout
    end

    # use only if all socket writes are fast
    # does not wait for a read
    def fast_connect_get(path = nil, dly: nil, len: nil)
      req = "GET /#{path} HTTP/1.1\r\n".dup
      req << "Dly: #{dly}\r\n" if dly
      req << "Len: #{len}\r\n" if len
      req << "\r\n"
      fast_connect_raw req
    end

    # Use to send a raw string, keyword parameters are the same as `fast_connect`.
    #
    def fast_connect_raw(str = nil, type: nil, p: nil)
      s = fast_connect type: type, p: p
      s.fast_write str
      s
    end

    # Used to open a socket.  Normally, the connection info is supplied by calling `bind_type`,
    # but that can be set manually if needed for control sockets, etc.
    # @param type: [Symbol] the type of connection, eg, :tcp, :ssl, :aunix, :unix
    # @param p: [String, Integer] the port or path of the connection
    #
    def fast_connect(type: nil, p: nil)
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
          SktUnix.new path.sub(/\A@/, "\0")
        end
      @ios_to_close << skt
      skt
    end

    # Creates a stream of client sockets
    #
    # The response body must contain 'Hello World' on a line.
    #
    # ### Write Errors
    # * Ubuntu & macOS
    #   * tcp: Errno::ECONNREFUSED
    #   * unix: Errno::EPIPE, Errno::ENOENT
    #
    # rubocop:disable Metrics/ParameterLists
    def create_clients(replies, threads, clients_per_thread,
      dly_thread: 0.005, dly_client: 0.005, dly_app: nil,
      body_kb: 10, keep_alive: false, req_per_client: 1, resp_timeout: 10)

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
      refused_errors = thread_run_refused

      mutex_w     = Mutex.new
      mutex_r_ok  = Mutex.new
      mutex_r_bad = Mutex.new

      threads.times do |thread|
        client_threads << Thread.new do
          sleep(dly_thread * thread) if dly_thread
          clients_per_thread.times do
            socket = nil
            open_write_err = false
            req_per_client.times do |req_idx|
              time_st = Time.now
              begin
                if req_idx.zero?
                  socket = fast_connect_get dly: dly_app, len: body_kb
                else
                  socket.get dly: dly_app, len: body_kb
                end
                replies[:reqs_good_wr][req_idx] += 1 if use_reqs
              rescue *OPEN_WRITE_ERRORS => e
                # unix Errno::ENOENT, darwin - Errno::ECONNRESET
                mutex_w.synchronize {
                  replies[:refused_errs_write][e.class.to_s] += 1
                  replies[:refused_write] += 1
                }
                open_write_err = true if req_per_client > 1
              else
                begin
                  body = socket.read_body resp_timeout
                  time_end = Time.now
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
              sleep dly_client if dly_client
              break if open_write_err
            end
          end
        end
      end
      client_threads
    end

    def msg_from_replies(replies)
      colors = {
        red:     "\e[31;1m",
        green:   "\e[32;1m",
        yellow:  "\e[33;1m",
        blue:    "\e[34;1m",
        magenta: "\e[35;1m",
        cyan:    "\e[36;1m"
      }
      reset = "\e[0m"

      c = -> (str, key, clr) {
        t = replies.fetch(key,0)
        t.zero? ? "   %4d #{str}\n" % t : "#{colors[clr]}   %4d #{str}#{reset}\n" % t
      }

      msg =  c.call('read bad response', :bad_response , :red).dup
      msg << c.call('read refused*'    , :refused      , :red)
      msg << c.call('read reset'       , :reset        , :red)
      msg << c.call('read timeout'     , :timeout      , :red)
      msg << c.call('write refused*'   , :refused_write, :yellow)
      msg << c.call('success'          , :success      , :green)

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

    # Generates the request/response time distribution string
    #
    def time_info(threads, clients_per_thread, time_ary, req_per_client = 1)
      good_requests  = time_ary.length
      total_requests = threads * clients_per_thread * req_per_client

      rpc = req_per_client == 1 ? '1 request per client' :
        "#{req_per_client} requests per client"

      str = "(#{threads} loops of #{clients_per_thread} clients * #{rpc})"

      ret = ''.dup

      if total_requests == good_requests
        ret << "#{time_ary.length} successful requests #{str} - total request time\n"
      else
        ret << "#{time_ary.length} successful requests #{str} - total request time, BAD REQUESTS #{total_requests - good_requests}\n"
      end

      return "#{ret}\nNeed at least 20 good requests for timing, only have #{good_requests}" if good_requests < 20

      idxs = []
      fmt_vals = '%2s'.dup
      hdr = '     '.dup
      v = ['  mS']

      time_ary.sort!

      time_min = time_ary.first

      [0.05, 0.1, 0.2, 0.4, 0.5, 0.6, 0.8, 0.9, 0.95].each { |n|
        idxs << (good_requests * n).ceil
        fmt_vals << (time_min < 500 ? '  %6.2f' : '  %6.0f')
        hdr << format('  %6s', "#{(100*n).to_i}% ")
      }
      hdr << "\n"

      idxs.each { |i| v << (time_ary[i] + time_ary[i-1])/2 }

      ret << "#{hdr}#{format fmt_vals, *v}\n"
      ret
    end

    # used to define correct 'refused' errors
    def thread_run_refused
      if @bind_type == :unix
        ary = IS_OSX ? [Errno::EBADF, Errno::ENOENT] :
          [Errno::ENOENT]
      else
        ary = IS_OSX ? [Errno::EBADF, Errno::ECONNREFUSED, Errno::EPIPE, EOFError] :
          [Errno::EBADF, Errno::ECONNREFUSED]  # intermittent Errno::EBADF with ssl?
      end
      ary << Errno::ECONNABORTED if IS_WINDOWS
      ary.freeze
    end
  end
end
