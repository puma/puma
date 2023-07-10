class CustomLogger
  def initialize(output=STDOUT)
    @output = output
  end

  def write(msg)
    @output.puts 'Custom logging: ' + msg
    @output.flush
  end
end

log_requests
custom_logger CustomLogger.new(STDOUT)
