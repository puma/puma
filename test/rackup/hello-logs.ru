require 'logger'
class AppWithLogger
  def initialize
    @logger = Logger.new('test/log.log')
  end

  def call(env)
    @logger.info "hello"
    [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
  end
end

run AppWithLogger.new
