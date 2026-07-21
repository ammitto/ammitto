# frozen_string_literal: true

module Ammitto
  module Extractors
    # Registry for managing extractors
    #
    # Provides a central location to register and retrieve
    # source extractors.
    #
    # @example Registering an extractor
    #   Registry.register(:eu, EuExtractor)
    #
    # @example Getting an extractor
    #   extractor = Registry.get(:eu)
    #
    class Registry
      # @return [Hash<Symbol, Class>] registered extractors
      @extractors = {}

      class << self
        # Register an extractor
        # @param code [Symbol] source code
        # @param klass [Class] extractor class
        # @return [void]
        def register(code, klass)
          @extractors[code.to_sym] = klass
        end

        # Get an extractor by source code
        # @param code [Symbol] source code
        # @return [Class, nil] extractor class
        def get(code)
          load_extractor(code)

          @extractors[code.to_sym]
        end

        # Get all registered extractor codes
        # @return [Array<Symbol>] source codes
        def codes
          @extractors.keys
        end

        # Check if extractor exists for code
        # @param code [Symbol] source code
        # @return [Boolean]
        def exists?(code)
          @extractors.key?(code.to_sym) || extractor_defined?(code)
        end

        private

        # Load extractor class for code (lazy loading)
        # @param code [Symbol] source code
        # @return [void]
        def load_extractor(code)
          return if @extractors.key?(code.to_sym)

          # Try to auto-load
          begin
            case code.to_sym
            when :eu
              require_relative 'eu_extractor'
            when :un
              require_relative 'un_extractor'
            when :us
              require_relative 'us_extractor'
            when :wb
              require_relative 'wb_extractor'
            when :uk
              require_relative 'uk_extractor'
            when :au
              require_relative 'au_extractor'
            when :ca
              require_relative 'ca_extractor'
            when :ch
              require_relative 'ch_extractor'
            when :cn
              require_relative 'cn_extractor'
            when :ru
              require_relative 'ru_extractor'
            when :tr
              require_relative 'tr_extractor'
            when :nz
              require_relative 'nz_extractor'
            when :eu_vessels
              require_relative 'eu_vessels_extractor'
            when :un_vessels
              require_relative 'un_vessels_extractor'
            when :jp
              require_relative 'jp_extractor'
            end
          rescue LoadError
            # Extractor not available
          end
        end

        # Check if extractor class is defined for code
        # @param code [Symbol] source code
        # @return [Boolean]
        def extractor_defined?(code)
          extractor_name = "#{code}_extractor"
          begin
            require_relative extractor_name
            true
          rescue LoadError
            false
          end
        end
      end
    end
  end
end
