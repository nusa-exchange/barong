# frozen_string_literal: true

module Services
  module HealthChecker
    # TODO: add check for kafka
    LIVENESS_CHECKS = %i[check_db check_redis].freeze
    READINESS_CHECKS = %i[check_db].freeze

    class << self
      def alive?
        check! LIVENESS_CHECKS
      rescue StandardError => e
        Rails.logger.error "#{e.message}\n#{e.backtrace[0..5].join("\n")}"
        false
      end

      def ready?
        check! READINESS_CHECKS
      rescue StandardError => e
        Rails.logger.error "#{e.message}\n#{e.backtrace[0..5].join("\n")}"
        false
      end

      private

      def check!(checks)
        checks.all? { |m| send(m) }
      end

      def check_db
        Permission.count
        ActiveRecord::Base.connected?
      end

      def check_redis
        Rails.cache.redis.ping == 'PONG'
      end
    end
  end
end
