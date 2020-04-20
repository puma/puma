module Minitest
  # Adds minimal support for parallel tests to the default verbose progress reporter.
  def self.plugin_verbose_progress_init(options)
    if options[:verbose]
      self.reporter.reporters.
        delete_if {|r| r.is_a?(ProgressReporter)}.
        push(VerboseProgressReporter.new(options[:io], options))
    end
  end

  # Verbose progress reporter that supports parallel test execution.
  class VerboseProgressReporter < Reporter
    def prerecord(klass, name)
      @current ||= nil
      @current = [klass.name, name].tap(&method(:print_start))
    end

    def record(result)
      print_start [result.klass, result.name]
      @current = nil
      io.print "%.2f s = " % [result.time]
      io.print result.result_code
      io.puts
    end

    def print_start(test)
      unless @current == test
        io.puts '…' if @current
        io.print "%s#%s = " % test
        io.flush
      end
    end
  end
end
