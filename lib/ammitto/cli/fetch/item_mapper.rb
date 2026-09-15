# frozen_string_literal: true

require_relative '../../errors/base_error'

module Ammitto
  module Cmd
    module Fetch
      module ItemMapper
        private

        # Get items collection from parsed data
        # @param source [Symbol] source code
        # @param data [Object] parsed data
        # @return [Array] collection of items
        def items_from_data(source, data)
          case source
          when :uk
            data.designations || []
          when :eu
            data.sanction_entities || []
          when :un
            (data.all_individuals || []) + (data.all_entities || [])
          when :us
            data.entries || []
          when :wb
            data.firms || []
          when :au
            (data.individuals || []) + (data.organizations || []) + (data.vessels || [])
          when :ca
            data.records || []
          when :ch
            data.all_identities || []
          when :cn
            data.all_entities || data.entities || []
          when :ru
            data.all_entities || data.entities || []
          when :tr
            data.entities || []
          when :nz
            (data.individuals || []) + (data.entities || []) + (data.ships || [])
          when :eu_vessels
            data.vessels || []
          when :jp
            data.entities || []
          when :un_vessels
            data.vessels || []
          else
            []
          end
        end

        # Generate filename for an item
        #
        # @param source [Symbol] source code
        # @param item [Object] the item
        # @return [String] filename
        # @raise [Ammitto::ParseError] when the record carries no identifier
        def filename_for_item(source, item)
          ref = identifier_for_item(source, item)
          raise identifierless_error(source) if ref.nil?

          filename_from_ref(source, ref)
        end

        # The first identifier a source actually carries, or nil.
        #
        # Every candidate goes through `presence`, because the `||` chains
        # this replaces only caught nil. An empty string is truthy in Ruby,
        # so a Canadian record whose id was "" took the first branch and
        # produced `ca-.yaml` — seven bytes of `--- {}` that failed
        # harmonize's health gate and blocked both `ammitto/data` and the
        # site build from 2026-08-25 until it was found two days later.
        #
        # @param source [Symbol] source code
        # @param item [Object] the item
        # @return [String, nil] the identifier, or nil when it has none
        def identifier_for_item(source, item)
          case source
          when :uk then presence(item.unique_id)
          when :eu then presence(item.eu_reference_number)
          when :un then presence(item.reference_number)
          when :us then presence(item.uid)
          when :wb then presence(item.supp_id)
          when :au then presence(item.reference) || presence(item.id)
          when :ca then presence(item.generate_id) || presence(item.item)
          when :ch then presence(item.ssid) || presence(item.full_name&.gsub(/\s+/, '-'))
          when :cn then presence(item.english_name) || presence(item.chinese_name)
          when :ru then presence(item.english_name) || presence(item.russian_name)
          when :tr
            # local_id, not reference_number: Turkey assigns one "Sıra No"
            # to two organisations, and local_id is what tells them apart.
            # Harmonize mints IRIs from the same method, so a record that
            # gets its own file here also gets its own graph node.
            presence(item.local_id) || presence(item.name)
          when :nz then presence(item.unique_identifier) || presence(item.reference_number)
          when :eu_vessels then presence(item.imo_number) || presence(item.unique_identifier)
          when :jp then presence(item.id) || presence(item.unique_identifier)
          when :un_vessels
            # local_id, not unique_identifier: the fallback identity for
            # the one vessel listed without an IMO number must be its
            # name slug, which is stable across harvests — the previous
            # unique_identifier fallback stringified a nil IMO into the
            # constant ref "IMO-".
            presence(item.local_id)
          end
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

        # Nil for a value that is absent or blank; the value otherwise.
        #
        # @param value [Object, nil]
        # @return [Object, nil]
        def presence(value)
          return nil if value.nil?
          return nil if value.to_s.strip.empty?

          value
        end

        # @param source [Symbol] source code
        # @return [Ammitto::ParseError]
        def identifierless_error(source)
          Ammitto::ParseError.new(
            "#{source}: a record carries no usable identifier. Writing it " \
            'would name a file after an id the source did not supply, and ' \
            'harmonize refuses such a record downstream; refusing here ' \
            'instead of publishing an empty one.'
          )
        end
      end
    end
  end
end
