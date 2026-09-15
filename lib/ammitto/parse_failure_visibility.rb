# frozen_string_literal: true

require_relative 'config/override_resolver'

module Ammitto
  module ParseFailureVisibility
    THREAD_KEY = :ammitto_parse_failure_run

    class Run
      def initialize
        @counts = Hash.new(0)
      end

      def record(source)
        @counts[source.to_sym] += 1
      end

      def count(source)
        @counts.fetch(source.to_sym, 0)
      end
    end

    module_function

    def with_run(run = Run.new)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = run
      yield run
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def current_run
      Thread.current[THREAD_KEY]
    end

    def report(source:, field:, value:, error: nil)
      current_run&.record(source)

      failure = ParseFailureError.new(
        source: source,
        field: field,
        value: value,
        original_error: error
      )

      case mode
      when :silent
        nil
      when :warn
        Logger.warn(failure.message)
        nil
      when :raise
        Logger.warn(failure.message)
        raise failure
      end
    end

    def mode
      raw = Config::OverrideResolver.new(
        parse_failure_mode: Ammitto.configuration.parse_failure_mode
      ).resolve(:parse_failure_mode)

      normalized = raw.to_s.strip.downcase.to_sym
      return normalized if Config::Defaults::PARSE_FAILURE_MODES.include?(normalized)

      raise ConfigurationError.new(
        "Invalid parse failure mode: #{raw.inspect}; " \
        "expected one of #{Config::Defaults::PARSE_FAILURE_MODES.join(', ')}",
        key: :parse_failure_mode
      )
    end
  end
end
