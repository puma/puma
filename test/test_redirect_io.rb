require_relative "helper"
require_relative "helpers/integration"

class TestRedirectIO < TestIntegration
  parallelize_me!

  def setup
    super

    @out_file_path = Tempfile.new('puma-out').path
    @err_file_path = Tempfile.new('puma-err').path
  end

  def teardown
    super

    paths = [@out_file_path, @err_file_path, @old_out_file_path, @old_err_file_path].compact
    File.unlink(*paths)
  end

  def test_sighup_redirects_io_single
    skip_on :jruby # Server isn't coming up in CI, TODO Fix
    skip_unless_signal_exist? :HUP

    cli_args = [
      '--redirect-stdout', @out_file_path,
      '--redirect-stderr', @err_file_path,
      'test/rackup/hello.ru'
    ]
    cli_server cli_args.join ' '

    wait_until_file_has_content @out_file_path
    assert_match 'puma startup', File.read(@out_file_path)

    wait_until_file_has_content @err_file_path
    assert_match 'puma startup', File.read(@err_file_path)

    log_rotate_output_files

    Process.kill :HUP, @server.pid

    wait_until_file_has_content @out_file_path
    assert_match 'puma startup', File.read(@out_file_path)

    wait_until_file_has_content @err_file_path
    assert_match 'puma startup', File.read(@err_file_path)
  end

  def test_sighup_redirects_io_cluster
    skip_unless_signal_exist? :HUP

    cli_args = [
      '-w', '1',
      '--redirect-stdout', @out_file_path,
      '--redirect-stderr', @err_file_path,
      'test/rackup/hello.ru'
    ]
    cli_server cli_args.join ' '

    wait_until_file_has_content @out_file_path
    assert_match 'puma startup', File.read(@out_file_path)

    wait_until_file_has_content @err_file_path
    assert_match 'puma startup', File.read(@err_file_path)

    log_rotate_output_files

    Process.kill :HUP, @server.pid

    wait_until_file_has_content @out_file_path
    assert_match 'puma startup', File.read(@out_file_path)

    wait_until_file_has_content @err_file_path
    assert_match 'puma startup', File.read(@err_file_path)
  end

  private

  def log_rotate_output_files
    # rename both files to .old
    @old_out_file_path = "#{@out_file_path}.old"
    @old_err_file_path = "#{@err_file_path}.old"
    File.rename @out_file_path, @old_out_file_path
    File.rename @err_file_path, @old_err_file_path

    File.new(@out_file_path, File::CREAT).close
    File.new(@err_file_path, File::CREAT).close
  end

  def wait_until_file_has_content(path)
    File.open(path) do |file|
      begin
        file.read_nonblock 1
        file.seek 0
      rescue EOFError
        sleep 0.1
        retry
      end
    end
  end
end
