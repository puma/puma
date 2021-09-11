# frozen_string_literal: true

require 'optparse'

module TestPuma
  class BenchBase

    # Signal used to trigger worker GC
    GC_SIGNAL = 'SIGALRM'

    # We're running under GitHub Actions
    IS_GHA = ENV['GITHUB_ACTIONS'] == 'true'

    WRK_PERCENTILE = [0.50, 0.75, 0.9, 0.99, 1.0].freeze

    def initialize
      sleep 5 # wait for server to boot

      @thread_loops       = nil
      @clients_per_thread = nil
      @req_per_client     = nil
      @body_kb            = 10
      @dly_app            = nil
      @bind_type          = :tcp

      @ios_to_close = []

      setup_options

      unless File.exist? @state_file
        puts "can't fined state file '#{@state_file}'"
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
      when :ssl, :tcp
        @bind_port = ENV.fetch('PORT', 40010).to_i
      when :unix
        @bind_path = "#{Dir.home}/skt.unix"
      when :aunix
        @bind_path = "@skt.aunix"
      else
        exit 1
      end
    end

    def setup_options
      OptionParser.new do |o|
        o.on "-l", "--loops LOOPS", OptionParser::DecimalInteger, "create_clients: loops/threads" do |arg|
          @thread_loops = arg.to_i
        end

        o.on "-c", "--connections CONNECTIONS", OptionParser::DecimalInteger, "create_clients: clients_per_thread" do |arg|
          @clients_per_thread = arg.to_i
        end

        o.on "-r", "--requests REQUESTS", OptionParser::DecimalInteger, "create_clients: requests per client" do |arg|
          @req_per_client = arg.to_i
        end

        o.on "-b", "--body_kb BODYKB", OptionParser::DecimalInteger, "CI RackUp: size of response body in kB" do |arg|
          @body_kb = arg.to_i
        end

        o.on "-d", "--dly_app DELAYAPP", Float, "CI RackUp: app response delay" do |arg|
          @dly_app = arg.to_f
        end

        o.on "-s", "--socket SOCKETTYPE", String, "Bind type: tcp, ssl, unix, aunix" do |arg|
          @bind_type = arg.to_sym
        end

        o.on "-S", "--state STATEFILE", String, "Puma Server: state file" do |arg|
          @state_file = arg
        end

        o.on "-t", "--threads THREADS", String, "Puma Server: threads" do |arg|
          @threads = arg[/\d+\z/].to_i
        end

        o.on "-w", "--workers WORKERS", OptionParser::DecimalInteger, "Puma Server: workers" do |arg|
          @workers = arg.to_i
        end

        o.on "-T", "--time TIME", OptionParser::DecimalInteger, "wrk: duration" do |arg|
          @wrk_time = arg.to_i
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
      puts "Closed #{closed} clients" unless closed.zero?
    end

    def run_wrk_parse(cmd)
      print cmd.ljust 55

      wrk_output = %x[#{cmd}]

      wrk_data = "#{wrk_output[/\A.+ connections/m]}\n#{wrk_output[/  Thread Stats.+\z/m]}"

      print " |#{wrk_data[/^ +\d+ +requests.+/].rstrip}\n"

      # puts '', wrk_data, ''     # for debugging or output format changes

      hsh = {}

      hsh[:rps]      = wrk_data[/^Requests\/sec: +([\d.]+)/, 1].to_f.round
      hsh[:requests] = wrk_data[/^ +(\d+) +requests/, 1].to_i
      if (t = wrk_data[/^ +Socket errors: +(.+)/, 1])
        hsh[:errors] = t
      end

      read = wrk_data[/ +([\d.]+)(GB|KB|MB) +read$/, 1].to_f
      unit = wrk_data[/ +[\d.]+(GB|KB|MB) +read$/, 1]

      mult =
        case unit
        when 'KB' then 1_024
        when 'MB' then 1_024**2
        when 'GB' then 1_024**3
        end

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

      hsh[:times] = WRK_PERCENTILE.zip(latency.map do |t|
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

    def parse_stats
      obj = @puma_info.run 'stats'
      # puts ''; pp obj; puts ''
      wrks = obj[:worker_status]
      stats = {}
      wrks.each do |w|
        pid = w[:pid]
        req_cnt = w[:last_status][:requests_count]
        id = format 'worker-%01d-%02d', w[:phase], w[:index]
        hsh = {
          pid: w[:pid],
          requests: req_cnt - @worker_req_ttl[w[:pid]],
          backlog: w[:last_status][:backlog]
        }
        @pids[hsh[:pid]] = id
        @worker_req_ttl[pid] = req_cnt
        stats[id] = hsh
      end
      stats
    end

    def parse_smem
      @puma_info.run 'gc'
      sleep 1

      hsh_smem = Hash.new []
      pids = @pids.keys

      smem_info = %x[smem -c 'pid rss pss uss command']
      # puts '', smem_info, ''
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
end
