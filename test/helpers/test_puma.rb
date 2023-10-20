# frozen_string_literal: true

require 'socket'
require 'tmpdir'

# This module is included in `TesPuma::ServerBase` and contains methods used
# across the test framework.  It also includes a few class methods related to
# debug logging.

module TestPuma

  DEBUGGING_INFO = Queue.new
  DEBUGGING_PIDS = {}

  IS_GITHUB_ACTIONS = ENV['GITHUB_ACTIONS'] == 'true'

  AFTER_RUN_OK = [false]

  RE_HOST_TO_IP = /\A\[|\]\z/o

  RESP_SPLIT = "\r\n\r\n"
  LINE_SPLIT = "\r\n"

  HOST4 = begin
    t = Socket.ip_address_list.select(&:ipv4_loopback?).map(&:ip_address)
      .uniq.sort_by(&:length)
    # puts "IPv4 Loopback #{t}"
    str = t.include?('127.0.0.1') ? +'127.0.0.1' : +"#{t.first}"
    str.define_singleton_method(:ip) { self }
    str.freeze
  end

  HOST6 = begin
    t = Socket.ip_address_list.select(&:ipv6_loopback?).map(&:ip_address)
      .uniq.sort_by(&:length)
    # puts "IPv6 Loopback #{t}"
    str = t.include?('::1') ? +'[::1]' : +"[#{t.first}]"
    str.define_singleton_method(:ip) { self.gsub RE_HOST_TO_IP, '' }
    str.freeze
  end

  LOCALHOST = ENV.fetch 'PUMA_CI_DFLT_HOST', 'localhost'

  if ENV['PUMA_CI_DFLT_IP'] =='IPv6'
    HOST     = HOST6
    ALT_HOST = HOST4
  else
    HOST     = HOST4
    ALT_HOST = HOST6
  end

  DARWIN = RUBY_PLATFORM.include? 'darwin'

  TOKEN = "xxyyzz"

  def before_setup
    @files_to_unlink = nil
  end

  def after_teardown
    @files_to_unlink&.each do |path|
      begin
        File&.unlink path
      rescue Errno::ENOENT
      end
    end
  end

  # Returns an available port by using `TCPServer.open(host, 0)`
  def unique_port(host = HOST)
    host = host.gsub RE_HOST_TO_IP, ''
    TCPServer.open(host, 0) { |server| server.connect_address.ip_port }
  end

  alias_method :new_port, :unique_port

  # With some macOS configurations, the following error may be raised when
  # creating a UNIXSocket:
  #
  # too long unix socket path (106 bytes given but 104 bytes max) (ArgumentError)
  #
  PUMA_CI_TMPDIR =
    begin
      if ::Puma::IS_OSX
        # adds subdirectory 'tmp/ci' in repository folder
        dir_temp = File.absolute_path("#{__dir__}/../../tmp")
        Dir.mkdir(dir_temp) unless Dir.exist? dir_temp
        dir_temp += '/ci'
        Dir.mkdir(dir_temp) unless Dir.exist? dir_temp
        dir_temp
      elsif ENV['GITHUB_ACTIONS'] && (rt_dir = ENV['RUNNER_TEMP'])
        # GitHub runners temp may be on a HD, rt_dir is always an SSD
        rt_dir
      else
        Dir.tmpdir()
      end
    end

  UNUSABLE_CHARS = "^,-.0-9A-Z_a-z~"
  private_constant :UNUSABLE_CHARS

  # Dedicated random number generator
  RANDOM = Object.new
  class << RANDOM
    # Maximum random number
    MAX = 36**6 # < 0x100000000

    # Returns new random string upto 6 bytes
    def next
      rand(0x100000000).to_s(36)
    end
  end
  RANDOM.freeze
  private_constant :RANDOM

  # Generates a unique file path.  Optionally, writes to the file
  def unique_path(basename = '', dir: PUMA_CI_TMPDIR, contents: nil, io: nil)
    max_try = 10
    n = nil
    if basename.is_a? String
      prefix, suffix = '', basename
    else
      prefix, suffix = basename
    end
    prefix = (String.try_convert(prefix) or
              raise ArgumentError, "unexpected prefix: #{prefix.inspect}")
    prefix = prefix.delete(UNUSABLE_CHARS)
    suffix &&= (String.try_convert(suffix) or
                raise ArgumentError, "unexpected suffix: #{suffix.inspect}")
    suffix &&= suffix.delete(UNUSABLE_CHARS)

    loop do
      # 366235959999.to_s(36) => 4o8vfnb3, eight characters
      # dddhhmmss ms
      t = Time.now.strftime('%j%H%M%S%L').to_i.to_s(36).rjust 8, '0'
      path = "#{prefix}#{t}-#{RANDOM.next}"\
             "#{n ? %[-#{n}] : ''}#{suffix || ''}"
      path = File.join(dir, path)
      unless File.exist? path
        File.write(path, contents, perm: 0600, mode: 'wb') if contents
        (@files_to_unlink ||= []) << path
        return io ? File.open(path) : path
      end
      n ||= 0
      n += 1
      if n > max_try
        raise "cannot generate temporary name using `#{basename}' under `#{dir}'"
      end
    end
  end

  def with_env(env = {})
    original_env = {}
    env.each do |k, v|
      original_env[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    original_env.each do |k, v|
      v.nil? ? ENV.delete(k) : ENV[k] = v
    end
  end

  def kill_and_wait(pid, signal: nil, timeout: 10)
    signal ||= :TERM
    signal = :KILL if Puma::IS_WINDOWS
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    wait2_timeout pid, timeout: timeout
  end

  def wait2_timeout(pid, timeout: 10)
    ary = nil
    err_msg = "Timeout waiting Process.wait2 in after_teardown"

    th =  Thread.new do
      begin
        ary = Process.wait2 pid
      rescue Errno::ECHILD
      end
    end.join timeout

    raise(Timeout::Error, err_msg) unless th
    ary
  end

  module_function :kill_and_wait, :wait2_timeout

  def self.handle_defunct
    defunct = {}
    txt = +''
    loop do
      begin
        pid, status = Process.wait2(-1, Process::WNOHANG)
        break unless pid
        defunct[pid] = status unless ::Puma::IS_WINDOWS && status == 0
      rescue Errno::ECHILD
        break
      end
    end

    if defunct.empty?
      txt << format("\n\n%5d      Test Process\n", Process.pid)
    else
      dash = "\u2500"
      txt << (IS_GITHUB_ACTIONS ? "\n\n##[group]Child Processes:\n" :
        "\n\n#{dash * 40} Child Processes:\n")

      txt << "#{Process.pid}      Test Process\n"

      # list all children, kill test processes
      defunct.each do |pid, status|
        if (test_name = DEBUGGING_PIDS[pid])
          txt << format("%5d #{status&.exitstatus.to_s.rjust 3}  #{test_name}\n", pid)
          kill_and_wait pid
        else
          txt << format("%5d #{status&.exitstatus.to_s.rjust 3}  Unknown\n", pid)
        end
      end

      # kill unknown processes
      defunct.each do |pid, _|
        unless DEBUGGING_PIDS.key? pid
          kill_and_wait pid
        end
      end

      txt << (IS_GITHUB_ACTIONS ? "::[endgroup]\n\n" : "#{dash * 57}\n\n")
    end
    TestPuma::AFTER_RUN_OK[0] = true
    txt
  end

  def self.debugging_info
    info = ''
    if AFTER_RUN_OK[0] && ENV['PUMA_TEST_DEBUG'] && !DEBUGGING_INFO.empty?
      ary = Array.new(DEBUGGING_INFO.size) { DEBUGGING_INFO.pop }
      ary.sort!
      out = ary.join.strip
      unless out.empty?
        dash = "\u2500"
        wid = IS_GITHUB_ACTIONS ? 88 : 90
        txt = " Debugging Info #{dash * 2}".rjust wid, dash
        if IS_GITHUB_ACTIONS
          info = "\n\n##[group]#{txt}\n#{out}\n#{dash * wid}\n\n::[endgroup]\n\n"
        else
          info = "\n\n#{txt}\n#{out}\n#{dash * wid}\n\n"
        end
      end
    end
    info
  ensure
    DEBUGGING_INFO.close
  end
end
