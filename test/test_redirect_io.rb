require_relative "helper"
require_relative "helpers/integration"

class TestRedirectIO < TestIntegration
  parallelize_me!

  def setup
    super

    @out_file = Tempfile.new 'puma-out'
    @out_file_path = @out_file.path
    @err_file = Tempfile.new 'puma-err'
    @err_file_path = @err_file.path
  end

  def teardown
    super

    @out_file.close
    @err_file.close
    File.unlink @out_file_path
    File.unlink @err_file_path
  end

  def test_sighup_redirects_io_single
    skip_unless_signal_exist? :HUP

    cli_args = [
      '--redirect-stdout', @out_file_path,
      '--redirect-stderr', @err_file_path,
      'test/rackup/hello.ru'
    ]
    cli_server cli_args.join ' '

    wait_until_file_has_content @out_file
    assert_match 'puma startup', @out_file.readline

    wait_until_file_has_content @err_file
    assert_match 'puma startup', @err_file.readline

    log_rotate_output_files

    Process.kill :HUP, @server.pid

    wait_until_file_has_content @out_file
    assert_match 'puma startup', @out_file.readline

    wait_until_file_has_content @err_file
    assert_match 'puma startup', @err_file.readline
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

    wait_until_file_has_content @out_file
    assert_match 'puma startup', @out_file.readline

    wait_until_file_has_content @err_file
    assert_match 'puma startup', @err_file.readline

    log_rotate_output_files

    Process.kill :HUP, @server.pid

    wait_until_file_has_content @out_file
    assert_match 'puma startup', @out_file.readline

    wait_until_file_has_content @err_file
    assert_match 'puma startup', @err_file.readline
  end

  private

  def log_rotate_output_files
    # rename both files to .old
    old_out_file_path = "#{@out_file_path}.old"
    old_err_file_path = "#{@err_file_path}.old"
    File.rename @out_file_path, old_out_file_path
    File.rename @err_file_path, old_err_file_path

    # reload references to output files
    @out_file.close
    @err_file.close
    @out_file = File.open @out_file_path, File::CREAT
    @err_file = File.open @err_file_path, File::CREAT
  end

  def wait_until_file_has_content(file)
    file.read_nonblock 1
    file.seek 0
  rescue EOFError
    sleep 0.1
    retry
  end
end
