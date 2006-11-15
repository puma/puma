require 'thread'

# monkey patch Mutex so it does not leak memory.
class Mutex

  def lock
    while (Thread.critical = true; @locked)
      @waiting.unshift Thread.current
      Thread.stop
    end
    @locked = true
    Thread.critical = false
    self
  end
  
  def unlock
    return unless @locked
    Thread.critical = true
    @locked = false
    begin
      t = @waiting.pop
      t.wakeup if t
    rescue ThreadError
      retry
    end
    Thread.critical = false
    begin
      t.run if t
    rescue ThreadError
    end
    self
  end
  
end