# frozen_string_literal: true

module Ammitto
  # Registry manages source adapters
  #
  # Sources are registered with a code (e.g., :eu, :un, :us) and can be
  # looked up by that code.
  #
  # @example Registering a source
  #   Registry.register(:eu, EuSource)
  #
  # @example Getting a source
  #   source = Registry.get(:eu)
  #
  class Registry
    # Registered sources
    @sources = {}

    class << self
      # Register a source
      # @param code [Symbol] the source code
      # @param source_class [Class] the source class
      # @return [void]
      def register(code, source_class)
        @sources[code.to_sym] = source_class
      end

      # Get a source by code
      # @param code [Symbol] the source code
      # @return [BaseSource, nil] the source class or nil
      def get(code)
        @sources[code.to_sym]
      end

      # Check if a source is registered
      # @param code [Symbol] the source code
      # @return [Boolean]
      def registered?(code)
        @sources.key?(code.to_sym)
      end

      # Get all registered source codes
      # @return [Array<Symbol>]
      def codes
        @sources.keys.sort
      end

      # Get all registered sources
      # @return [Hash<Symbol, Class>]
      def all
        @sources.dup
      end

      # Get a source instance by code
      # @param code [Symbol] the source code
      # @return [BaseSource, nil] a new source instance
      def instance(code)
        source_class = get(code)
        return nil unless source_class

        source_class.new
      end

      # Clear all registered sources (for testing)
      # @return [void]
      def clear
        @sources = {}
      end
    end
  end
end
