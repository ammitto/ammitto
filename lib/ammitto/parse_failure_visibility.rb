# frozen_string_literal: true

require_relative 'config/override_resolver'
require_relative 'configuration'
require_relative 'error'
require_relative 'logger'

module Ammitto
  module ParseFailureVisibility
    THREAD_KEY = :ammitto_parse_failure_run
    SUPPRESS_REPORTING_KEY = :ammitto_suppress_parse_failure_reporting

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

    # Run a speculative transform without counting or warning about parse
    # failures, which the final transform pass reports instead. Returns the
    # block result and whether it reported a failure. Raise mode is the
    # exception: the raise drops the record before the final pass, so the
    # failure is counted, warned and raised here.
    def without_reporting
      previous = Thread.current[SUPPRESS_REPORTING_KEY]
      state = { failed: false }
      Thread.current[SUPPRESS_REPORTING_KEY] = state
      result = yield
      [result, state[:failed]]
    ensure
      Thread.current[SUPPRESS_REPORTING_KEY] = previous
    end

    def reporting_suppressed?
      Thread.current[SUPPRESS_REPORTING_KEY].is_a?(Hash)
    end

    def current_run
      Thread.current[THREAD_KEY]
    end

    def report(source:, field:, value:, error: nil)
      failure = ParseFailureError.new(
        source: source,
        field: field,
        value: value,
        original_error: error
      )

      # A raised failure drops the record before the final pass, so it is
      # reported here; anything else is reported by the final pass.
      if reporting_suppressed? && mode != :raise
        Thread.current[SUPPRESS_REPORTING_KEY][:failed] = true
        return nil
      end

      current_run&.record(source)

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
