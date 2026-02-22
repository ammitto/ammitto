# frozen_string_literal: true

require 'logger'

module Ammitto
  # Custom logger for Ammitto gem
  #
  # Provides logging functionality with configurable output and verbosity.
  #
  # @example Using the logger
  #   Ammitto::Logger.info("Fetching data from EU")
  #   Ammitto::Logger.debug("Cache hit for eu.jsonld")
  #   Ammitto::Logger.error("Failed to connect to API")
  #
  class Logger
    # Log levels matching Ruby's Logger
    LEVELS = {
      debug: ::Logger::DEBUG,
      info: ::Logger::INFO,
      warn: ::Logger::WARN,
      error: ::Logger::ERROR,
      fatal: ::Logger::FATAL
    }.freeze

    class << self
      # Get the logger instance
      # @return [::Logger] the logger instance
      def logger
        @logger ||= build_logger
      end

      # Set a custom logger
      # @param [::Logger, nil] custom_logger the custom logger to use
      # @return [void]
      attr_writer :logger

      # Log a debug message
      # @param [String] message the message to log
      # @return [void]
      def debug(message)
        log(:debug, message)
      end

      # Log an info message
      # @param [String] message the message to log
      # @return [void]
      def info(message)
        log(:info, message)
      end

      # Log a warning message
      # @param [String] message the message to log
      # @return [void]
      def warn(message)
        log(:warn, message)
      end

      # Log an error message
      # @param [String] message the message to log
      # @return [void]
      def error(message)
        log(:error, message)
      end

      # Log a fatal message
      # @param [String] message the message to log
      # @return [void]
      def fatal(message)
        log(:fatal, message)
      end

      private

      # Build a default logger instance
      # @return [::Logger] the built logger
      def build_logger
        logger = ::Logger.new($stderr)
        logger.level = default_log_level
        logger.formatter = method(:format_message).to_proc
        logger
      end

      # Get the default log level based on configuration
      # @return [Integer] the log level
      def default_log_level
        Ammitto.configuration.verbose ? ::Logger::DEBUG : ::Logger::INFO
      end

      # Format a log message
      # @param [String] severity the severity level
      # @param [Time] _datetime the timestamp
      # @param [String] _progname the program name
      # @param [String] msg the message
      # @return [String] the formatted message
      def format_message(severity, _datetime, _progname, msg)
        "[ammitto] #{severity}: #{msg}\n"
      end

      # Log a message at the specified level
      # @param [Symbol] level the log level
      # @param [String] message the message to log
      # @return [void]
      def log(level, message)
        return unless LEVELS.key?(level)

        use_custom_logger = Ammitto.configuration.logger
        target = use_custom_logger || logger
        target.send(level, message)
      end
    end
  end
end
