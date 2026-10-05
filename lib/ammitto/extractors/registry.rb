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
      # Where the extractor files live.
      EXTRACTOR_DIR = __dir__

      # Sources with an extractor file. Only these codes ever become a
      # path, so a code like "../x" cannot reach a file outside the list.
      EXTRACTORS = %i[eu un us wb uk au ca ch cn ru tr nz eu_vessels un_vessels jp].freeze

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

          path = extractor_path(code)
          require path if path
        end

        # Check if extractor class is defined for code
        # @param code [Symbol] source code
        # @return [Boolean]
        def extractor_defined?(code)
          path = extractor_path(code)
          return false unless path

          require path
          true
        end

        # Only an absent extractor file means "no extractor": the callers
        # require the path this returns unguarded, so a LoadError from
        # inside a file that exists (its own require of a missing gem) is
        # a broken extractor and surfaces instead of reading as N/A.
        # @param code [Symbol] source code
        # @return [String, nil] the extractor file, when it exists
        def extractor_path(code)
          return unless EXTRACTORS.include?(code.to_sym)

          path = File.join(EXTRACTOR_DIR, "#{code}_extractor.rb")
          path if File.file?(path)
        end
      end
    end
  end
end
