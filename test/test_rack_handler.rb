require "test_helper"

require "rack/handler/puma"

class TestPumaUnixSocket < Minitest::Test
  def test_handler
    handler = Rack::Handler.get(:puma)
    assert_equal Rack::Handler::Puma, handler
    handler = Rack::Handler.get('Puma')
    assert_equal Rack::Handler::Puma, handler
  end
end

class TestPathHandler < Minitest::Test
  def app
    Proc.new {|env| @input = env; [200, {}, ["hello world"]]}
  end

  def setup
    @input = nil
  end

  def in_handler(app, options = {})
    options[:Port] ||= 0
    options[:Silent] = true

    @launcher = nil
    thread = Thread.new do
      Rack::Handler::Puma.run(app, options) do |s, p|
        @launcher = s
      end
    end
    thread.abort_on_exception = true

    # Wait for launcher to boot
    Timeout.timeout(10) do
      until @launcher
        sleep 1
      end
    end
    sleep 1

    yield @launcher
  ensure
    @launcher.stop if @launcher
    thread.join  if thread
  end


  def test_handler_boots
    in_handler(app) do |launcher|
      hit(["http://0.0.0.0:#{ launcher.connected_port }/test"])
      assert_equal("/test", @input["PATH_INFO"])
    end
  end

  # def test_user_supplied_port_wins_over_config_file
  #   user_port = 5001
  #   file_port = 6001
  #   options = {}

  #   Tempfile.open("puma.rb") do |f|
  #     f.puts "port #{file_port}"
  #     f.close

  #     options[:config_files]          = [f.path]
  #     options[:user_supplied_options] = [:Port]
  #     options[:Port]                  = user_port

  #     conf = Rack::Handler::Puma.config(app, options)
  #     conf.load
  #     assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
  #   end
  # end

  def test_default_port_loses_to_config_file
    user_port = 5001
    file_port = 6001
    options = {}

    Dir.mktmpdir do |d|
      Dir.chdir(d) do
        FileUtils.mkdir("config")
        File.open("config/puma.rb", "w") { |f| f << "port #{6001}" }

        conf = Rack::Handler::Puma.config(app, options)
        conf.load

        assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
      end
    end
  end
end
