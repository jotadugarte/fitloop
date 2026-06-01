# frozen_string_literal: true

module Analytics
  class Thresholds
    CONFIG_PATH = Rails.root.join("config/analytics.yml")
    LOCK = Mutex.new

    def self.funnel_conversion_min_percent
      config[:funnel_conversion_min_percent] || 15
    end

    def self.payment_failure_rate_max_percent
      config[:payment_failure_rate_max_percent] || 20
    end

    def self.nest_duration_p95_max_seconds
      config[:nest_duration_p95_max_seconds] || 600
    end

    def self.low_priority_events_per_hour
      config[:low_priority_events_per_hour] || 300
    end

    def self.funnel_breached?(percent)
      percent.to_f < funnel_conversion_min_percent
    end

    def self.payment_failure_breached?(percent)
      percent.to_f > payment_failure_rate_max_percent
    end

    def self.nest_duration_breached?(seconds)
      seconds.to_f > nest_duration_p95_max_seconds
    end

    private

    def self.config
      current_mtime = File.exist?(CONFIG_PATH) ? File.mtime(CONFIG_PATH) : nil
      LOCK.synchronize do
        if @config.nil? || @last_mtime != current_mtime
          @config = load_config
          @last_mtime = current_mtime
        end
        @config
      end
    end

    def self.load_config
      if File.file?(CONFIG_PATH)
        YAML.load_file(CONFIG_PATH)&.symbolize_keys || {}
      else
        {}
      end
    end
  end
end
