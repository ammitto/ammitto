# frozen_string_literal: true

require_relative 'jp_announcement_transform'

module Ammitto
  module Cmd
    module Harmonize
      # The transform_<source> methods whose source picks between record
      # shapes before delegating: a field combination (AU), a
      # target/identity wrapper (CH), an announcement/modification split
      # (CN), a type field (NZ), or an announcement/flat-record split (JP).
      # The fixed-shape RU, TR, and EU_VESSELS transforms are also here,
      # placed alongside them purely to keep both modules under the
      # Metrics/ModuleLength budget. SourceTransforms's dispatch table
      # (#transform_data) still routes every source, this one included,
      # through one call.
      module MultiShapeSourceTransforms
        include JpAnnouncementTransform

        private

        # Transform AU data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_au(transformer, data)
          # Detect record type: vessels carry imo_number, individuals carry
          # dates_of_birth; the rest are organizations
          source = if data.key?('imo_number')
                     Ammitto::Sources::Au::Vessel.from_hash(data)
                   elsif data.key?('dates_of_birth')
                     Ammitto::Sources::Au::Individual.from_hash(data)
                   else
                     Ammitto::Sources::Au::Organization.from_hash(data)
                   end
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform CH data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_ch(transformer, data)
          guard_announcement_format!(:ch, data,
                                     expected: 'Ch::Identity or Ch::Target')

          # SanctionsList#all_identities returns `targets`, so `fetch ch`
          # writes Target-shaped YAML (ssid, sanctions_set_id and an
          # individual:/entity: wrapper). Decide by the record's own shape
          # rather than by that method's name: a Target-shaped hash forced
          # through Identity.from_hash yields an Identity whose every
          # attribute is nil, and Identity#person? then raises
          # NoMethodError on nil.names. Ch::Transformer#transform already
          # branches on both classes.
          source = if ch_target_shape?(data)
                     Ammitto::Sources::Ch::Target.from_hash(data)
                   else
                     Ammitto::Sources::Ch::Identity.from_hash(data)
                   end
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Whether a CH record is a <target> wrapper rather than a bare
        # <identity>. A target carries sanctions_set_id and/or the
        # individual:/entity: wrapper; an identity carries names and
        # day_month_year at the top level.
        # @param data [Hash] source data
        # @return [Boolean]
        def ch_target_shape?(data)
          return false unless data.is_a?(Hash)

          data.key?('individual') || data.key?('entity') ||
            data.key?('sanctions_set_id')
        end

        # Transform CN data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash, Array<Hash>] single result or array of results
        def transform_cn(transformer, data)
          # Check if this is the new data-cn YAML format
          if data.key?('announcement') && data.key?('sanction_details')
            transform_cn_announcement(transformer, data)
          elsif data.key?('announcement') && data.key?('measure_modifications')
            transform_cn_modification(transformer, data)
          else
            # Only the announcement and modification shapes are supported;
            # anything else is a data defect the health gates must see, not a
            # record to skip.
            raise 'Unsupported CN source format (expected announcement-based YAML)'
          end
        end

        # Transform CN announcement (new YAML format)
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Array<Hash>] array of transformation results
        def transform_cn_announcement(transformer, data)
          announcement = Ammitto::Sources::Cn::Announcement.from_hash(data)
          result = transformer.transform_announcement(announcement)

          # Export SanctionGroup if present
          @exporter.add_group(result[:group], source: :cn) if result[:group]

          # Return array of entity/entry pairs
          result[:entities].zip(result[:entries]).map do |entity, entry|
            {
              entity: entity_to_hash(entity),
              entry: entry_to_hash(entry)
            }
          end
        end

        # Transform CN modification (new YAML format)
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash] empty entity/entry pair for a modification
        def transform_cn_modification(transformer, data)
          modification = Ammitto::Sources::Cn::MeasureModification.from_hash(data)
          transformer.transform_modification(modification)

          # Modifications amend an existing entity rather than adding one; the
          # ingest path treats a nil pair as a designed skip.
          {
            entity: nil,
            entry: nil
          }
        end

        # Transform RU data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_ru(transformer, data)
          source = Ammitto::Sources::Ru::SanctionedEntity.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform NZ data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_nz(transformer, data)
          # Determine type
          source = case data['type']
                   when 'Individual'
                     Ammitto::Sources::Nz::Individual.from_hash(data)
                   when 'Ship'
                     Ammitto::Sources::Nz::Ship.from_hash(data)
                   else
                     Ammitto::Sources::Nz::Entity.from_hash(data)
                   end
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform TR data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_tr(transformer, data)
          source = Ammitto::Sources::Tr::Entity.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform EU Vessels data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_eu_vessels(transformer, data)
          source = Ammitto::Sources::EuVessels::Vessel.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform JP data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash, Array<Hash>] single result or array of results
        def transform_jp(transformer, data)
          return transform_jp_announcement(transformer, data) if
            jp_announcement?(data)

          source = Ammitto::Sources::Jp::Entity.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end
      end
    end
  end
end
