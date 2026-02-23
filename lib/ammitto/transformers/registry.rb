# frozen_string_literal: true

require_relative 'base_transformer'

# Load transformers from source directories
require_relative '../sources/uk/transformer'
require_relative '../sources/eu/transformer'
require_relative '../sources/un/transformer'
require_relative '../sources/us/transformer'
require_relative '../sources/wb/transformer'
require_relative '../sources/au/transformer'
require_relative '../sources/ca/transformer'
require_relative '../sources/ch/transformer'
require_relative '../sources/cn/transformer'
require_relative '../sources/ru/transformer'
require_relative '../sources/nz/transformer'
require_relative '../sources/tr/transformer'

module Ammitto
  module Transformers
    # Registry provides access to source-specific transformers
    #
    # @example Getting a transformer
    #   transformer = Transformers::Registry.get(:uk)
    #   result = transformer.transform(source_model)
    #
    class Registry
      # Registered transformers by source code (using new co-located classes)
      TRANSFORMERS = {
        uk: Ammitto::Sources::Uk::Transformer,
        eu: Ammitto::Sources::Eu::Transformer,
        un: Ammitto::Sources::Un::Transformer,
        us: Ammitto::Sources::Us::Transformer,
        wb: Ammitto::Sources::Wb::Transformer,
        au: Ammitto::Sources::Au::Transformer,
        ca: Ammitto::Sources::Ca::Transformer,
        ch: Ammitto::Sources::Ch::Transformer,
        cn: Ammitto::Sources::Cn::Transformer,
        ru: Ammitto::Sources::Ru::Transformer,
        nz: Ammitto::Sources::Nz::Transformer,
        tr: Ammitto::Sources::Tr::Transformer
      }.freeze

      class << self
        # Get a transformer for a source
        # @param source_code [Symbol, String] the source code
        # @return [BaseTransformer, nil] the transformer instance
        def get(source_code)
          transformer_class = TRANSFORMERS[source_code.to_sym]
          return nil unless transformer_class

          transformer_class.new
        end

        # Get all registered transformers
        # @return [Hash<Symbol, BaseTransformer>] map of source codes to transformers
        def all
          TRANSFORMERS.transform_values(&:new)
        end

        # Get list of supported source codes
        # @return [Array<Symbol>]
        def supported_sources
          TRANSFORMERS.keys
        end

        # Check if a source is supported
        # @param source_code [Symbol, String] the source code
        # @return [Boolean]
        def supported?(source_code)
          TRANSFORMERS.key?(source_code.to_sym)
        end
      end
    end
  end
end
