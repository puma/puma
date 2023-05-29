require_relative "helper"
require_relative "helpers/integration"

class TestWorkerGemIndependence < TestIntegration
  class PumaBooted < Timeout::Error; end

  def setup
    super
  end

  def teardown
    FileUtils.rm_rf ["#{workdir}/vendor", "#{workdir}/Gemfile.lock"]
  end

  def test_prevent_booting_with_rack_3
    puma_crashed = false

    Dir.chdir(workdir) do
      with_unbundled_env do
        silent_and_checked_system_command("bundle install")
        Timeout.timeout(1, PumaBooted) do
          cli_server './config.ru', merge_err: true, skip_waiting: true
          sleep 0.1 until puma_crashed = @server.gets["Puma 5 is not compatible with Rack 3, please upgrade to Puma 6 or higher."]
        end
      end
    end

  rescue PumaBooted
    puma_crashed = false
  ensure
    Process.kill :HUP, @server.pid
    assert puma_crashed, "Puma was expected to crash on boot, but it didn't! "
  end

  private

  def workdir
    File.expand_path("bundle_rack_3", __dir__)
  end
end
