# frozen_string_literal: true

module Ammitto
  # Base error class for all Ammitto errors
  #
  # All custom errors in Ammitto inherit from this class,
  # allowing for easy rescue of any Ammitto-specific error.
  #
  # @example Catching all Ammitto errors
  #   begin
  #     Ammitto.search("test")
  #   rescue Ammitto::Error => e
  #     puts "Ammitto error: #{e.message}"
  #   end
  #
  class Error < StandardError
    # @return [String, nil] Additional context about the error
    attr_reader :context

    # Initialize the error with a message and optional context
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String] :context additional context
    def initialize(message, options = {})
      @context = options[:context]
      super(message)
    end

    # @return [String] Full error message including context
    def full_message
      return super unless context

      "#{super} (Context: #{context})"
    end
  end

  # Error raised for network-related failures
  #
  # @example
  #   raise Ammitto::NetworkError.new("Connection refused", context: "https://example.com")
  #
  class NetworkError < Error
    # @return [Integer, nil] HTTP status code if applicable
    attr_reader :status_code

    # @return [String, nil] The URL that failed
    attr_reader :url

    # Initialize the network error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [Integer] :status_code HTTP status code
    # @option options [String] :url the URL that failed
    # @option options [String] :context additional context
    def initialize(message, options = {})
      @status_code = options[:status_code]
      @url = options[:url]
      super(message, options)
    end

    # @return [String] Full error message including status code and URL
    def full_message
      parts = [super]
      parts << "URL: #{url}" if url
      parts << "Status: #{status_code}" if status_code
      parts.join(' | ')
    end
  end

  # Error raised for cache-related failures
  #
  # @example
  #   raise Ammitto::CacheError.new("Cache directory not writable")
  #
  class CacheError < Error
    # @return [String, nil] The cache path involved
    attr_reader :path

    # Initialize the cache error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String] :path the cache path
    def initialize(message, options = {})
      @path = options[:path]
      super(message, options)
    end
  end

  # Error raised for validation failures
  #
  # @example
  #   raise Ammitto::ValidationError.new("Invalid entity type", field: "entity_type")
  #
  class ValidationError < Error
    # @return [String, nil] The field that failed validation
    attr_reader :field

    # @return [Array<String>, nil] List of validation errors
    attr_reader :errors

    # Initialize the validation error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String] :field the field that failed
    # @option options [Array<String>] :errors list of validation errors
    def initialize(message, options = {})
      @field = options[:field]
      @errors = options[:errors]
      super(message, options)
    end
  end

  # Error raised when a source is not found or not registered
  #
  # @example
  #   raise Ammitto::SourceNotFoundError.new("Unknown source: xyz")
  #
  class SourceNotFoundError < Error
    # @return [String, Symbol, nil] The source code that was not found
    attr_reader :source_code

    # Initialize the source not found error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String, Symbol] :source_code the source code
    def initialize(message, options = {})
      @source_code = options[:source_code]
      super(message, options)
    end
  end

  # Error raised for parsing failures
  #
  # @example
  #   raise Ammitto::ParseError.new("Invalid JSON", format: :json)
  #
  class ParseError < Error
    # @return [Symbol, nil] The format that failed to parse
    attr_reader :format

    # @return [String, nil] The original content that failed to parse
    attr_reader :content

    # Initialize the parse error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [Symbol] :format the format (:json, :xml, :yaml)
    # @option options [String] :content the original content
    def initialize(message, options = {})
      @format = options[:format]
      @content = options[:content]
      super(message, options)
    end
  end

  # Error raised for serialization failures
  #
  # @example
  #   raise Ammitto::SerializationError.new("Failed to serialize entity")
  #
  class SerializationError < Error
    # @return [Class, nil] The class that failed to serialize
    attr_reader :object_class

    # Initialize the serialization error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [Class] :object_class the class of the object
    def initialize(message, options = {})
      @object_class = options[:object_class]
      super(message, options)
    end
  end

  # Error raised when a requested resource is not found
  #
  # @example
  #   raise Ammitto::NotFoundError.new("Entity not found", id: "123")
  #
  class NotFoundError < Error
    # @return [String, nil] The ID of the resource not found
    attr_reader :resource_id

    # Initialize the not found error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String] :id the resource ID
    def initialize(message, options = {})
      @resource_id = options[:id]
      super(message, options)
    end
  end

  # Error raised for configuration-related failures
  #
  # @example
  #   raise Ammitto::ConfigurationError.new("Invalid cache directory")
  #
  class ConfigurationError < Error
    # @return [String, nil] The configuration key that is invalid
    attr_reader :key

    # Initialize the configuration error
    # @param [String] message the error message
    # @param [Hash] options additional options
    # @option options [String] :key the configuration key
    def initialize(message, options = {})
      @key = options[:key]
      super(message, options)
    end
  end
end
