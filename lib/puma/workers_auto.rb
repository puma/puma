# frozen_string_literal: true

module Puma
  # Resolves the worker count for :auto / "auto" values.
  #
  # When running inside Kubernetes the node's total CPU count is visible via
  # Concurrent.available_processor_count, but the container's actual CPU
  # budget is enforced by cgroups.  This class reads the cgroup quota files
  # so Puma spawns the right number of workers even when the container limit
  # is much smaller than the node capacity.
  class WorkersAuto
    CGROUPS_V2_CPU_MAX   = '/sys/fs/cgroup/cpu.max'
    CGROUPS_V1_QUOTA_US  = '/sys/fs/cgroup/cpu/cpu.cfs_quota_us'
    CGROUPS_V1_PERIOD_US = '/sys/fs/cgroup/cpu/cpu.cfs_period_us'

    # Returns the resolved worker count as an Integer.
    def self.count
      require_processor_counter

      workers = cpu_count_from_cgroups
      return workers if workers && workers > 0

      Integer(::Concurrent.available_processor_count)
    end

    def self.require_processor_counter
      require 'concurrent/utility/processor_counter'
    rescue LoadError
      warn <<~MESSAGE
        WEB_CONCURRENCY=auto or workers(:auto) requires the "concurrent-ruby" gem to be installed.
        Please add "concurrent-ruby" to your Gemfile.
      MESSAGE
      raise
    end

    def self.cpu_count_from_cgroups
      if File.exist?(CGROUPS_V2_CPU_MAX)
        content = File.read(CGROUPS_V2_CPU_MAX).strip
        quota_str, period_str = content.split(' ', 2)
        return nil if quota_str == 'max'
        quota  = Integer(quota_str)
        period = Integer(period_str)
        return [1, (quota.to_f / period).ceil].max
      end

      if File.exist?(CGROUPS_V1_QUOTA_US) && File.exist?(CGROUPS_V1_PERIOD_US)
        quota = Integer(File.read(CGROUPS_V1_QUOTA_US).strip)
        return nil if quota == -1
        period = Integer(File.read(CGROUPS_V1_PERIOD_US).strip)
        return [1, (quota.to_f / period).ceil].max
      end

      nil
    rescue StandardError
      nil
    end

    private_class_method :cpu_count_from_cgroups, :require_processor_counter
  end
end
