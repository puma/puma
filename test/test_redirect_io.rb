# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestRedirectIO < TestIntegration
  parallelize_me!

  FILE_STR = 'puma startup'

  def setup
    skip_unless_signal_exist? :HUP

    # Keep the Tempfile instances alive to avoid being GC'd
    @out_file = Tempfile.new('puma-out')
    @err_file = Tempfile.new('puma-err')
    @out_file_path = @out_file.path
    @err_file_path = @err_file.path

    @cli_args = ['--redirect-stdout', @out_file_path,
      '--redirect-stderr', @err_file_path,
      'test/rackup/hello.ru'
    ]

  end

  def teardown
    return if skipped?

    paths = (skipped? ? [@out_file_path, @err_file_path] :
      [@out_file_path, @err_file_path, @old_out_file_path, @old_err_file_path]).compact

    File.unlink(*paths)
    @out_file = nil
    @err_file = nil
  end

  def test_sighup_redirects_io_single
    skip_if :jruby # Server isn't coming up in CI, TODO Fix

    cli_server @cli_args.join ' '

    rotate_check_logs
  end

  def test_sighup_redirects_io_cluster
    skip_unless :fork

    cli_server (['-w', '1'] + @cli_args).join ' '

    rotate_check_logs
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

  def rotate_check_logs
    assert_file_contents @out_file_path
    assert_file_contents @err_file_path

    log_rotate_output_files

    Process.kill :HUP, @pid

    assert_file_contents @out_file_path
    assert_file_contents @err_file_path
  end

  def assert_file_contents(path, include = FILE_STR)
    retries = 0
    retries_max = 50 # 5 seconds
    File.open(path) do |file|
      begin
        file.read_nonblock 1
        file.seek 0
        assert_includes file.read, include,
          "File #{File.basename(path)} does not include #{include}"
      rescue EOFError
        sleep 0.1
        retries += 1
        if retries < retries_max
          retry
        else
          flunk 'File read took too long'
        end
      end
    end
  end
end
