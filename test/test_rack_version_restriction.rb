require_relative "helper"
require_relative "helpers/integration"

class TestRackVersionRestriction < TestIntegration
  class PumaBooted < Timeout::Error; end

  def setup
    # Rack 3 minimum Ruby version is 2.4
    skip if !::Puma::IS_MRI || RUBY_VERSION < '2.4'
    super
  end

  def teardown
    return if skipped?
    FileUtils.rm_rf ["#{workdir}/vendor", "#{workdir}/Gemfile.lock"]
    begin
      # KILL works with all OS's
      Process.kill(:KILL, @server.pid) if @server
    rescue Errno::ESRCH
    end
  end

  def test_prevent_booting_with_rack_3
    msg = "Puma 5 is not compatible with Rack 3"
    puma_crashed = false

    Dir.chdir(workdir) do
      with_unbundled_env do
        silent_and_checked_system_command("bundle config --local path vendor/bundle")
        silent_and_checked_system_command("bundle install")
        Timeout.timeout(5, PumaBooted) do
          cli_server './config.ru', merge_err: true, skip_waiting: true
          sleep 0.1 until puma_crashed = @server.gets[msg]
        end
      end
    end

  rescue PumaBooted
  ensure
    assert puma_crashed, "Puma was expected to crash on boot, but it didn't! "
  end

  private

  def workdir
    File.expand_path("bundle_rack_3", __dir__)
  end
end
