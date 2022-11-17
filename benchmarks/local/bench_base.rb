# frozen_string_literal: true

require 'optparse'

module TestPuma

  HOST4 = ENV.fetch('PUMA_TEST_HOST4', '127.0.0.1')
  HOST6 = ENV.fetch('PUMA_TEST_HOST6', '::1')
  PORT  = ENV.fetch('PUMA_TEST_PORT', 40001).to_i

  # Array of response body sizes.  If specified, set by ENV['PUMA_TEST_SIZES']
  #
  SIZES = if (t = ENV['PUMA_TEST_SIZES'])
    t.split(',').map(&:to_i).freeze
  else
    [1, 10, 100, 256, 512, 1024, 2048].freeze
  end

  TYPES = [[:a, 'array'].freeze, [:c, 'chunk'].freeze,
    [:s, 'string'].freeze, [:i, 'io'].freeze].freeze

  # Creates files used by 'i' (File/IO) responses.  Placed in
  # "#{Dir.tmpdir}/.puma_response_body_io"
  # @param sizes [Array <Integer>] Array of sizes
  #
  def self.create_io_files(sizes = SIZES)
    require 'tmpdir'
    tmp_folder = "#{Dir.tmpdir}/.puma_response_body_io"
    Dir.mkdir(tmp_folder) unless Dir.exist? tmp_folder
    fn_format = "#{tmp_folder}/body_io_%04d.txt"
    str = ("── Puma Hello World! ── " * 31) + "── Puma Hello World! ──\n"  # 1 KB
    sizes.each do |len|
      suf = format "%04d", len
      fn = format fn_format, len
      unless File.exist? fn
        body = "Hello World\n#{str}".byteslice(0,1023) + "\n" + (str * (len-1))
        File.write fn, body
      end
    end
  end

  # Base class for generating client request streams
  #
  class BenchBase
    # We're running under GitHub Actions
    IS_GHA = ENV['GITHUB_ACTIONS'] == 'true'

    WRK_PERCENTILE = [0.50, 0.75, 0.9, 0.99, 1.0].freeze

    HDR_BODY_CONF = "Body-Conf: "

    # extracts 'type' string from `-b` argument
    TYPES_RE = /\A[acis]+/.freeze

    # extracts 'size' string from `-b` argument
    SIZES_RE = /\d[\d,]*\z/.freeze

    def initialize
      sleep 5 # wait for server to boot

      @thread_loops       = nil
      @clients_per_thread = nil
      @req_per_client     = nil
      @body_sizes         = SIZES
      @body_types         = TYPES
      @dly_app            = nil
      @bind_type          = :tcp

      @ios_to_close = []

      setup_options

      unless File.exist? @state_file
        puts "Can't find state file '#{@state_file}'"
        exit 1
      end

      mstr_pid = File.binread(@state_file)[/^pid: +(\d+)/, 1].to_i
      begin
        Process.kill 0, mstr_pid
      rescue Errno::ESRCH
        puts 'Puma server stopped?'
        exit 1
      rescue Errno::EPERM
      end

      case @bind_type
      when :ssl, :ssl4, :tcp, :tcp4
        @bind_host = HOST4
        @bind_port = PORT
      when :ssl6, :tcp6
        @bind_host = HOST6
        @bind_port = PORT
      when :unix
        @bind_path = 'tmp/benchmark_skt.unix'
      when :aunix
        @bind_path = '@benchmark_skt.aunix'
      else
        exit 1
      end
    end

    def setup_options
      OptionParser.new do |o|
        o.on "-T", "--stream-threads THREADS", OptionParser::DecimalInteger, "request_stream: loops/threads" do |arg|
          @stream_threads = arg.to_i
        end

        o.on "-c", "--wrk-connections CONNECTIONS", OptionParser::DecimalInteger, "request_stream: clients_per_thread" do |arg|
          @wrk_connections = arg.to_i
        end

        o.on "-R", "--requests REQUESTS", OptionParser::DecimalInteger, "request_stream: requests per socket" do |arg|
          @req_per_socket = arg.to_i
        end

        o.on "-D", "--duration DURATION", OptionParser::DecimalInteger, "wrk/stream: duration" do |arg|
          @duration = arg.to_i
        end

        o.on "-b", "--body_conf BODY_CONF", String, "CI RackUp: type and size of response body in kB" do |arg|
          if (types = arg[TYPES_RE])
            @body_types = TYPES.select { |a| types.include? a[0].to_s }
          end

          if (sizes = arg[SIZES_RE])
            @body_sizes = sizes.split(',')
            @body_sizes.map!(&:to_i)
            @body_sizes.sort!
          end
        end

        o.on "-d", "--dly_app DELAYAPP", Float, "CI RackUp: app response delay" do |arg|
          @dly_app = arg.to_f
        end

        o.on "-s", "--socket SOCKETTYPE", String, "Bind type: tcp, ssl, tcp6, ssl6, unix, aunix" do |arg|
          @bind_type = arg.to_sym
        end

        o.on "-S", "--state PUMA_STATEFILE", String, "Puma Server: state file" do |arg|
          @state_file = arg
        end

        o.on "-t", "--threads PUMA_THREADS", String, "Puma Server: threads" do |arg|
          @threads = arg
        end

        o.on "-w", "--workers PUMA_WORKERS", OptionParser::DecimalInteger, "Puma Server: workers" do |arg|
          @workers = arg.to_i
        end

        o.on "-W", "--wrk_bind WRK_STR", String, "wrk: bind string" do |arg|
          @wrk_bind_str = arg
        end

        o.on("-h", "--help", "Prints this help") do
          puts o
          exit
        end
      end.parse! ARGV
    end

    def close_clients
      closed = 0
      @ios_to_close.each do |socket|
        if socket && socket.to_io.is_a?(IO) && !socket.closed?
          begin
            if @bind_type == :ssl
              socket.sysclose
            else
              socket.close
            end
            closed += 1
          rescue Errno::EBADF
          end
        end
      end
      puts "Closed #{closed} sockets" unless closed.zero?
    end

    # Runs wrk and returns data from its output.
    # @param cmd [String] The wrk command string, with arguments
    # @return [Hash] The wrk data
    #
    def run_wrk_parse(cmd, log: false)
      STDOUT.syswrite cmd.ljust 55

      if @dly_app
        cmd.sub! ' -H ', " -H 'Dly: #{@dly_app.round 4}' -H "
      end

      wrk_output = %x[#{cmd}]
      if log
        puts '', wrk_output, ''
      end

      wrk_data = "#{wrk_output[/\A.+ connections/m]}\n#{wrk_output[/  Thread Stats.+\z/m]}"

      ary = wrk_data[/^ +\d+ +requests.+/].strip.split ' '

      fmt = " | %6s %s %s %7s %8s %s\n"

      STDOUT.syswrite format(fmt, *ary)

      hsh = {}

      rps      = wrk_data[/^Requests\/sec: +([\d.]+)/, 1].to_f
      requests = wrk_data[/^ +(\d+) +requests/, 1].to_i

      transfer = wrk_data[/^Transfer\/sec: +([\d.]+)/, 1].to_f
      transfer_unit = wrk_data[/^Transfer\/sec: +[\d.]+(GB|KB|MB)/, 1]
      transfer_mult = mult_for_unit transfer_unit

      read = wrk_data[/ +([\d.]+)(GB|KB|MB) +read$/, 1].to_f
      read_unit = wrk_data[/ +[\d.]+(GB|KB|MB) +read$/, 1]
      read_mult = mult_for_unit read_unit

      resp_transfer = (transfer * transfer_mult)/rps
      resp_read = (read * read_mult)/requests.to_f

      mult = transfer/read

      hsh[:resp_size] = ((resp_transfer * mult + resp_read)/(mult + 1)).round

      hsh[:resp_size] = hsh[:resp_size] - 1770 - hsh[:resp_size].to_s.length

      hsh[:rps]       = rps.round
      hsh[:requests]  = requests

      if (t = wrk_data[/^ +Socket errors: +(.+)/, 1])
        hsh[:errors] = t
      end

      read = wrk_data[/ +([\d.]+)(GB|KB|MB) +read$/, 1].to_f
      unit = wrk_data[/ +[\d.]+(GB|KB|MB) +read$/, 1]

      mult = mult_for_unit unit

      hsh[:read] = (mult * read).round

      if hsh[:errors]
        t = hsh[:errors]
        hsh[:errors] = t.sub('connect ', 'c').sub('read ', 'r')
          .sub('write ', 'w').sub('timeout ', 't')
      end

      t_re = ' +([\d.ums]+)'

      latency =
         wrk_data.match(/^ +50%#{t_re}\s+75%#{t_re}\s+90%#{t_re}\s+99%#{t_re}/).captures
      # add up max time
      latency.push wrk_data[/^ +Latency.+/].split(' ')[-2]

      hsh[:times_summary] = WRK_PERCENTILE.zip(latency.map do |t|
        if t.end_with?('ms')
          t.to_f
        elsif t.end_with?('us')
          t.to_f/1000
        elsif t.end_with?('s')
          t.to_f * 1000
        else
          0
        end
      end).to_h
      hsh
    end

    def mult_for_unit(unit)
      case unit
      when 'KB' then 1_024
      when 'MB' then 1_024**2
      when 'GB' then 1_024**3
      end
    end

    # Outputs info about the run.  Example output:
    #
    #     benchmarks/local/response_time_wrk.sh -w2 -t5:5 -s tcp6
    #     Server cluster mode -w2 -t5:5, bind: tcp6
    #     Puma repo branch 00-response-refactor
    #     ruby 3.2.0dev (2022-06-11T12:26:03Z master 28e27ee76e) +YJIT [x86_64-linux]
    #
    def env_log
      puts "#{ENV['PUMA_BENCH_CMD']} #{ENV['PUMA_BENCH_ARGS']}"
      puts @workers ?
        "Server cluster mode -w#{@workers} -t#{@threads}, bind: #{@bind_type}" :
        "Server single mode -t#{@threads}, bind: #{@bind_type}"

      branch = %x[git branch][/^\* (.*)/, 1]
      if branch
        puts "Puma repo branch #{branch.strip}", RUBY_DESCRIPTION
      else
        const = File.read File.expand_path('../../lib/puma/const.rb', __dir__)
        puma_version = const[/^ +PUMA_VERSION[^'"]+['"]([^\s'"]+)/, 1]
        puts "Puma version #{puma_version}", RUBY_DESCRIPTION
      end
    end

    # Parses data returned by `PumaInfo.run stats`
    # @return [Hash] The data from Puma stats
    #
    def parse_stats
      stats = {}

      obj = @puma_info.run 'stats'

      worker_status = obj[:worker_status]

      worker_status.each do |w|
        pid = w[:pid]
        req_cnt = w[:last_status][:requests_count]
        id = format 'worker-%01d-%02d', w[:phase], w[:index]
        hsh = {
          pid: pid,
          requests: req_cnt - @worker_req_ttl[pid],
          backlog: w[:last_status][:backlog]
        }
        @pids[pid] = id
        @worker_req_ttl[pid] = req_cnt
        stats[id] = hsh
      end

      stats
    end

    # Runs gc in the server, then parses data from
    # `smem -c 'pid rss pss uss command'`
    # @return [Hash] The data from smem
    #
    def parse_smem
      @puma_info.run 'gc'
      sleep 1

      hsh_smem = Hash.new []
      pids = @pids.keys

      smem_info = %x[smem -c 'pid rss pss uss command']

      smem_info.lines.each do |l|
        ary = l.strip.split ' ', 5
        if pids.include? ary[0].to_i
          hsh_smem[@pids[ary[0].to_i]] = {
            pid: ary[0].to_i,
            rss: ary[1].to_i,
            pss: ary[2].to_i,
            uss: ary[3].to_i
          }
        end
      end
      hsh_smem.sort.to_h
    end
  end

  class ResponseTimeBase < BenchBase
    def run
      @puma_info = PumaInfo.new ['-S', @state_file]
    end

    # Prints summarized data. Example:
    # ```
    # Body    ────────── req/sec ──────────   ─────── req 50% times ───────
    #  KB     array   chunk  string      io   array   chunk  string      io
    # 1       13760   13492   13817    9610   0.744   0.759   0.740   1.160
    # 10      13536   13077   13492    9269   0.759   0.785   0.760   1.190
    # ```
    #
    # @param summaries [Hash] generated in subclasses
    #
    def overall_summary(summaries)
      names = +''
      @body_types.each { |_, t_desc| names << t_desc.rjust(8) }

      puts "\nBody    ────────── req/sec ──────────   ─────── req 50% times ───────" \
        "\n KB  #{names.ljust 32}#{names}"

      len = @body_types.length
      digits = [4 - Math.log10(@max_050_time).to_i, 3].min

      fmt_rps = ('%6d  ' * len).strip
      fmt_times = (digits < 0 ? "  %6d" : "  %6.#{digits}f") * len

      @body_sizes.each do |size|
        line = format '%-5d  ', size
        resp = ''
        line << format(fmt_rps  , *@body_types.map { |_, t_desc| summaries[size][t_desc][:rps] }).ljust(30)
        line << format(fmt_times, *@body_types.map { |_, t_desc| summaries[size][t_desc][:times_summary][0.5] })
        puts line
      end
      puts '─' * 69
    end
  end

end
