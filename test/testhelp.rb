def redirect_test_io
  orig_err = STDERR.dup
  orig_out = STDOUT.dup
  STDERR.reopen("test_stderr.log")
  STDOUT.reopen("test_stdout.log")

  begin
    yield
  ensure
    STDERR.reopen(orig_err)
    STDOUT.reopen(orig_out)
  end
end
