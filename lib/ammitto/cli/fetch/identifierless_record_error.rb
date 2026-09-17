# frozen_string_literal: true

require_relative '../../errors/base_error'

module Ammitto
  module Cmd
    module Fetch
      # Raised when a fetched record carries no identifier a filename can
      # be built from.
      #
      # The message lives here, not at the call site, so the wording is
      # one thing to change rather than one thing to find: ItemMapper only
      # names which source failed, and does not also have to restate why
      # that matters every time it raises.
      class IdentifierlessRecordError < Ammitto::ParseError
        # @param source [Symbol] the source code the record came from
        def initialize(source)
          super(
            "#{source}: a record carries no usable identifier. Writing " \
            'it would name a file after an id the source did not supply, ' \
            'and harmonize refuses such a record downstream; refusing ' \
            'here instead of publishing an empty one.'
          )
        end
      end
    end
  end
end
