# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/integration'

class TestIntegrationHelpers < PumaTest
  class ProbeTimeout < Exception; end

  def setup
    @integration = TestIntegration.new('helper_probe')
    @integration.setup
    @reader, @writer = IO.pipe
    @integration.instance_variable_set(:@server, @reader)
  end

  def teardown
    @writer.close unless @writer.closed?
    @reader.close unless @reader.closed?
  end

  def test_custom_timeout_with_silent_server
    error = within_probe_deadline do
      assert_raises(Minitest::Assertion) { wait_for_match(/ready/, timeout: 0.05) }
    end
    assert_includes error.message, 'Timeout'
    assert_includes error.message, 'ready'
  end

  def test_unmatched_lines_do_not_reset_deadline
    writer = Thread.new do
      loop do
        @writer.write "still starting\n"
        sleep 0.005
      end
    rescue IOError, Errno::EPIPE
    end
    error = within_probe_deadline do
      assert_raises(Minitest::Assertion) { wait_for_match(/ready/, timeout: 0.05) }
    end
    assert_includes error.message, 'still starting'
  ensure
    writer&.kill
    writer&.join
  end

  def test_partial_line_does_not_block_past_deadline
    @writer.write 'partial startup output'
    error = within_probe_deadline do
      assert_raises(Minitest::Assertion) { wait_for_match(/ready/, timeout: 0.05) }
    end
    assert_includes error.message, 'partial startup output'
  end

  def test_eof_reports_captured_output
    @writer.write "startup failed\nunfinished"
    @writer.close
    error = within_probe_deadline do
      assert_raises(Minitest::Assertion) { wait_for_match(/ready/) }
    end
    assert_includes error.message, 'closed'
    assert_includes error.message, "startup failed\nunfinished"
  end

  def test_buffered_lines_are_preserved_for_later_waits
    @writer.write "first\nsecond\n"
    @writer.close
    assert_equal "first\n", wait_for_match(/first/)
    assert_equal "second\n", wait_for_match(/second/)
  end

  def test_fragmented_line_can_match
    @writer.write 'rea'
    writer = Thread.new { sleep 0.01; @writer.write "dy\n" }
    assert_equal "ready\n", wait_for_match(/ready/, timeout: 1)
  ensure
    writer&.join
  end

  def test_final_line_without_newline_can_match
    @writer.write 'ready'
    @writer.close
    assert_equal 'ready', wait_for_match(/ready/)
  end

  def test_watchdog_exception_is_not_retried
    error = TimeoutPrepend::TestTookTooLong.new('watchdog')
    @reader.stub(:wait_readable, ->(*) { raise error }) do
      assert_same error, assert_raises(TimeoutPrepend::TestTookTooLong) {
        wait_for_match(/ready/)
      }
    end
  end

  def test_string_wait_uses_deadline
    within_probe_deadline do
      assert_raises(Minitest::Assertion) {
        @integration.send(:wait_for_server_to_include, 'ready', timeout: 0.05)
      }
    end
  end

  def test_shutdown_kills_and_reaps_unresponsive_child
    skip_unless :fork
    child = IO.popen([Gem.ruby, '-e', "STDOUT.sync = true; Signal.trap('TERM') {}; puts 'ready'; sleep 60"], pgroup: true)
    assert child.wait_readable(5), 'child did not start'
    assert_equal "ready\n", child.gets
    pid = child.pid
    @integration.instance_variable_set(:@pid, pid)
    @integration.instance_variable_set(:@server_process_group, pid)
    error = within_probe_deadline do
      assert_raises(Minitest::Assertion) { @integration.send(:stop_server, timeout: 0.05) }
    end
    assert_includes error.message, 'exit'
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
  ensure
    if child
      Process.kill(:KILL, -pid) rescue Errno::ESRCH if pid
      Process.waitpid(pid) rescue Errno::ECHILD if pid
      child.close unless child.closed?
    end
  end

  def test_shutdown_drains_output_and_returns_exit_status
    skip_unless :fork
    script = "STDOUT.sync = true; Signal.trap('TERM') { STDOUT.write('x' * 262144); exit }; puts 'ready'; sleep 60"
    child = IO.popen([Gem.ruby, '-e', script], pgroup: true)
    assert child.wait_readable(5), 'child did not start'
    assert_equal "ready\n", child.gets
    pid = child.pid
    @integration.instance_variable_set(:@server, child)
    @integration.instance_variable_set(:@pid, pid)
    @integration.instance_variable_set(:@server_process_group, pid)
    result = within_probe_deadline { @integration.send(:stop_server, timeout: 1) }
    assert_equal pid, result.first
    assert_predicate result.last, :success?
  ensure
    if child
      Process.kill(:KILL, -pid) rescue Errno::ESRCH if pid
      Process.waitpid(pid) rescue Errno::ECHILD if pid
      child.close unless child.closed?
    end
  end

  def test_teardown_closes_resources_even_when_stopping_fails
    @integration.instance_variable_set(:@pid, Process.pid)
    file = Tempfile.create('puma-helper-cleanup')
    @integration.instance_variable_get(:@ios_to_close) << file
    @integration.stub(:stop_server, ->(**) { raise Minitest::Assertion, 'shutdown failed' }) do
      assert_raises(Minitest::Assertion) { @integration.teardown }
    end
    assert_predicate file, :closed?
    assert_predicate @reader, :closed?
    refute File.exist?(file.path)
  ensure
    file&.close unless file&.closed?
    File.unlink(file.path) if file && File.exist?(file.path)
  end

  private

  def within_probe_deadline(&block)
    Timeout.timeout(2, ProbeTimeout, &block)
  end

  def wait_for_match(pattern, timeout: nil)
    @integration.send(:wait_for_server_to_match, pattern, nil, timeout: timeout)
  end
end
