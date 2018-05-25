require 'concurrent'

class ThreadPoolWorker

  def initialize(configuration, counters, coordinators)
    @shutdown = false

    Thread.new(counters[:spawned]) do |s|
      # Thread name is new in Ruby 2.3
      Thread.current.name = 'puma %03i' % s if Thread.current.respond_to?(:name=)

      extra = configuration[:extra].map { |i| i.new }

      while true
        work = nil

        continue = true

        coordinators[:mutex].synchronize do
          while coordinators[:todo].empty?
            if counters[:trim_requested] > 0
              counters[:trim_requested] -= 1
              continue = false
              coordinators[:not_full].signal
            elsif @shutdown
              continue = false
            else
              counters[:waiting] += 1
              coordinators[:not_full].signal
              coordinators[:not_empty].wait coordinators[:mutex]
              counters[:waiting] -= 1
            end

            break unless continue
          end

          work = coordinators[:todo].shift if continue
        end

        break unless continue

        if configuration[:clean_thread_locals]
          ThreadPool.clean_thread_locals
        end

        begin
          configuration[:block].call(work, *extra)
        rescue Exception => e
          STDERR.puts "Error reached top of thread-pool: #{e.message} (#{e.class})"
        end
      end

      cleanup
    end
  end

  def shutdown!
    @shutdown = true
  end

private

  def cleanup
    coordinators[:mutex].synchronize do
      counters[:spawned] -= 1
      coordinators[:threads].delete th
    end
  end

end
