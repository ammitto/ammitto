# frozen_string_literal: true

require_relative '../../errors/base_error'
require_relative 'identifierless_record_error'

module Ammitto
  module Cmd
    module Fetch
      module ItemMapper
        private

        # Get items collection from parsed data
        #
        # Every source class this is called with (see SourceRegistry's
        # `source_model_class_for`) defines its own `#items`, so the branch
        # this replaced (one line of `data.<attr> || []` per source) is the
        # source's own job now, not this mapper's. `source` isn't used to
        # decide the shape any more, but the parameter stays: it's the only
        # thing an operator sees in a raised error if `data` is ever the
        # wrong object for the source that produced it.
        #
        # @param source [Symbol] source code, for error context only
        # @param data [Object] parsed data, expected to respond to `#items`
        # @return [Array] collection of items
        def items_from_data(source, data)
          return data.items if data.respond_to?(:items)

          raise Ammitto::ParseError,
                "#{source}: parsed data has no #items — every fetchable " \
                'source class defines it; this source is not wired ' \
                'through the automated fetch path'
        end

        # Generate filename for an item
        #
        # @param source [Symbol] source code
        # @param item [Object] the item
        # @return [String] filename
        # @raise [Ammitto::ParseError] when the record carries no identifier
        def filename_for_item(source, item)
          ref = identifier_for_item(source, item)
          raise IdentifierlessRecordError, source if ref.nil?

          filename_from_ref(source, ref)
        end

        # The identifier a source's item actually carries, or nil.
        #
        # This used to be a 16-branch `case` on `source` naming which
        # fields to try, each result then filtered by
        # `Ammitto::Utils::Presence.present?` here. The maintainer's own
        # suggestion: give every item class its own `#identifier` method
        # instead, the same way each source's LIST class already defines
        # its own `#items` (see `items_from_data` above) rather than
        # leaving this mapper to know which attribute holds the
        # collection. `source` is no longer used to decide anything here;
        # it stays in the signature only because `filename_for_item`
        # still needs it for the filename prefix.
        #
        # Presence-checking is now the item class's own job too — every
        # `#identifier` implementation calls `Ammitto::Utils::Presence`
        # itself, so the empty-string trap this method used to guard
        # against (see IdentifierlessRecordError and the git history of
        # this file) is guarded once per class instead of once here.
        #
        # @param _source [Symbol] source code, unused
        # @param item [Object] the item, expected to respond to `#identifier`
        # @return [String, nil] the identifier, or nil when it has none
        def identifier_for_item(_source, item)
          item.identifier
        end

        # Build the filename from an identifier the source does carry.
        #
        # The slug rules are unchanged from the `||`-chain version they
        # replace: every currently published record must keep exactly the
        # filename it has, or the next harvest renames the whole corpus.
        #
        # @param source [Symbol] source code
        # @param ref [String] the identifier
        # @return [String] filename
        def filename_from_ref(source, ref)
          case source
          when :uk, :eu, :un, :us
            "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
          when :wb then "wb-#{ref}.yaml"
          when :au then "au-#{ref}.yaml"
          when :ca then "ca-#{ref}.yaml"
          when :ch then "ch-#{ref}.yaml"
          when :cn, :ru, :tr, :nz
            "#{source.to_s.tr('_', '-')}-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
          when :eu_vessels then "eu-vessel-#{ref}.yaml"
          when :jp then "jp-#{ref}.yaml"
          when :un_vessels then "un-vessel-#{ref}.yaml"
          else "#{ref}.yaml"
          end
        end
      end
    end
  end
end
