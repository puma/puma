# frozen_string_literal: true

require 'socket'
require 'tmpdir'

module TestPuma

  DEBUGGING_INFO = Queue.new
  DEBUGGING_PIDS = {}

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

  # Returns an available port by using `TCPServer.open(host, 0)`
  def unique_port(host = HOST)
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
        (@tmp_paths ||= []) << path
        return io ? File.open(path) : path
      end
      n ||= 0
      n += 1
      if n > max_try
        raise "cannot generate temporary name using `#{basename}' under `#{dir}'"
      end
    end
  end
end
