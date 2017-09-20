require_relative "helper"

class TestEvents < Minitest::Test
  def test_null
    events = Puma::Events.null

    assert_instance_of Puma::NullIO, events.stdout
    assert_instance_of Puma::NullIO, events.stderr
    assert_equal events.stdout, events.stderr
  end

  def test_strings
    events = Puma::Events.strings

    assert_instance_of StringIO, events.stdout
    assert_instance_of StringIO, events.stderr
  end

  def test_stdio
    events = Puma::Events.stdio

    assert_equal STDOUT, events.stdout
    assert_equal STDERR, events.stderr
  end

  def test_register_callback_with_block
    res = false

    events = Puma::Events.null

    events.register(:exec) { res = true }

    events.fire(:exec)

    assert_equal true, res
  end

  def test_register_callback_with_object
    obj = Object.new

    def obj.res
      @res || false
    end

    def obj.call
      @res = true
    end

    events = Puma::Events.null

    events.register(:exec, obj)

    events.fire(:exec)

    assert_equal true, obj.res
  end

  def test_fire_callback_with_multiple_arguments
    res = []

    events = Puma::Events.null

    events.register(:exec) { |*args| res.concat(args) }

    events.fire(:exec, :foo, :bar, :baz)

    assert_equal [:foo, :bar, :baz], res
  end

  def test_on_booted_callback
    res = false

    events = Puma::Events.null

    events.on_booted { res = true }

    events.fire_on_booted!

    assert res
  end

  def test_log_writes_to_stdout
    out, _ = capture_io do
      Puma::Events.stdio.log("ready")
    end

    assert_equal "ready\n", out
  end

  def test_write_writes_to_stdout
    out, _ = capture_io do
      Puma::Events.stdio.write("ready")
    end

    assert_equal "ready", out
  end

  def test_debug_writes_to_stdout_if_env_is_present
    original_debug, ENV["PUMA_DEBUG"] = ENV["PUMA_DEBUG"], "1"

    out, _ = capture_io do
      Puma::Events.stdio.debug("ready")
    end

    assert_equal "% ready\n", out
  ensure
    ENV["PUMA_DEBUG"] = original_debug
  end

  def test_debug_not_write_to_stdout_if_env_is_not_present
    out, _ = capture_io do
      Puma::Events.stdio.debug("ready")
    end

    assert_empty out
  end

  def test_error_writes_to_stderr_and_exits
    did_exit = false

    _, err = capture_io do
      Puma::Events.stdio.error("interrupted")
    end

    assert_equal "ERROR: interrupted", err
  rescue SystemExit
    did_exit = true
  ensure
    assert did_exit
  end

  def test_pid_formatter
    pid = Process.pid

    out, _ = capture_io do
      events = Puma::Events.stdio

      events.formatter = Puma::Events::PidFormatter.new

      events.write("ready")
    end

    assert_equal "[#{ pid }] ready", out
  end

  def test_custom_log_formatter
    custom_formatter = proc { |str| "-> #{ str }" }

    out, _ = capture_io do
      events = Puma::Events.stdio

      events.formatter = custom_formatter

      events.write("ready")
    end

    assert_equal "-> ready", out
  end
end
