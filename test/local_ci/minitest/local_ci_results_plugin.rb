require "json"

module Minitest
  def self.plugin_local_ci_results_init(_options)
    return unless ENV["PUMA_TEST_RESULTS"]
    return if reporter.reporters.any?(LocalCiResultsReporter)
    reporter << LocalCiResultsReporter.new(ENV["PUMA_TEST_RESULTS"])
  end

  class LocalCiResultsReporter < AbstractReporter
    def initialize(path)
      @file = File.open(path, "a")
      @file.sync = true
      @mutex = Mutex.new
    end

    def record(result)
      file = result.source_location&.first
      line = {
        test: "#{result.klass}##{result.name}",
        file: file && File.basename(file),
        result: result.result_code,
        message: result.failure&.message.to_s.lines.first(3).join.strip
      }.to_json
      @mutex.synchronize { @file.puts line }
    end
  end
end
