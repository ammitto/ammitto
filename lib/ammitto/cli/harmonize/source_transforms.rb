# frozen_string_literal: true

require_relative 'multi_shape_source_transforms'

module Ammitto
  module Cmd
    module Harmonize
      # #transform_data's dispatch table, JSON-LD serialization helpers, the
      # announcement-format guard and its marker constants, plus the
      # transform_<source> methods for fixed-shape sources (UK, EU, UN, US,
      # WB, CA, and UN_VESSELS). The shape-branching sources (AU, CH, CN, NZ,
      # and JP), plus the fixed-shape RU, TR, and EU_VESSELS transforms, live
      # in MultiShapeSourceTransforms instead, split out purely to keep both
      # modules under the Metrics/ModuleLength budget. #transform_data still
      # dispatches every source, from either module, through this one table.
      #
      # No transform_<source> method requires its model class: every source
      # in Ammitto::Transformers::Registry has its Lutaml::Model classes
      # loaded already by lib/ammitto.rb's top-level `require_relative
      # 'sources/<code>/source'`, which each source's source.rb requires
      # in turn (e.g. sources/uk/source.rb requires designation.rb).
      # require_relative on an already-loaded path is not free — it does a
      # $LOADED_FEATURES lookup on every call — and #transform_data runs
      # once per record, so a per-method require here paid that cost on
      # every record of every source for no load it needed.
      module SourceTransforms
        include MultiShapeSourceTransforms

        # Raised when announcement-format YAML reaches a legacy per-entity
        # source path that cannot parse it safely.
        class AnnouncementFormatError < StandardError; end

        # Top-level YAML keys that mark the announcement format.
        ANNOUNCEMENT_FORMAT_KEYS = %w[announcement sanction_details
                                      measure_modifications].freeze

        private

        # Transform data using appropriate transformer
        # @param source [Symbol] source code
        # @param data [Hash] source data
        # @return [Hash] { entity: Hash, entry: Hash }
        def transform_data(source, data)
          transformer = Ammitto::Transformers::Registry.get(source)
          return { entity: nil, entry: nil } unless transformer

          # Transform based on source
          case source
          when :uk
            transform_uk(transformer, data)
          when :eu
            transform_eu(transformer, data)
          when :un
            transform_un(transformer, data)
          when :us
            transform_us(transformer, data)
          when :wb
            transform_wb(transformer, data)
          when :au
            transform_au(transformer, data)
          when :ca
            transform_ca(transformer, data)
          when :ch
            transform_ch(transformer, data)
          when :cn
            transform_cn(transformer, data)
          when :ru
            transform_ru(transformer, data)
          when :nz
            transform_nz(transformer, data)
          when :tr
            transform_tr(transformer, data)
          when :eu_vessels
            transform_eu_vessels(transformer, data)
          when :jp
            transform_jp(transformer, data)
          when :un_vessels
            transform_un_vessels(transformer, data)
          else
            { entity: nil, entry: nil }
          end
        end

        # Reject announcement-format YAML on a legacy per-entity path.
        # The error message names the format; the caller's per-file error
        # collector prefixes the offending filename, and the health gates
        # turn it into a non-zero exit.
        # @param source [Symbol] source code
        # @param data [Hash] source data
        # @param expected [String] the schema this path parses
        # @return [void]
        # @raise [AnnouncementFormatError] on announcement-shaped data
        def guard_announcement_format!(source, data, expected:)
          return unless data.is_a?(Hash)

          markers = ANNOUNCEMENT_FORMAT_KEYS & data.keys.map(&:to_s)
          return if markers.empty?

          raise AnnouncementFormatError,
                'announcement-format YAML detected (top-level ' \
                "#{markers.join(', ')}) — the #{source} path parses " \
                "per-entity #{expected} records, and announcement " \
                "ingestion is not implemented for #{source}; refusing " \
                'to harmonize this file'
        end

        # Transform UK data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_uk(transformer, data)
          guard_announcement_format!(:uk, data, expected: 'Uk::Designation')

          designation = Ammitto::Sources::Uk::Designation.from_hash(data)
          result = transformer.transform(designation)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform EU data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_eu(transformer, data)
          # The fetch pipeline saves Eu::SanctionEntity YAML (one per record);
          # parsing with ProcessedEntity collapsed every EU id and dropped names
          entity = Ammitto::Sources::Eu::SanctionEntity.from_hash(data)
          result = transformer.transform(entity)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform UN data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_un(transformer, data)
          # Determine if individual or entity based on presence of person-specific fields
          # UN data uses snake_case in YAML (first_name, not firstName)
          is_individual = data.key?('gender') ||
                          data.key?('date_of_birth') ||
                          data.key?('place_of_birth') ||
                          data.key?('documents') ||
                          data.key?('nationalities') ||
                          data.key?('fourth_name')

          if is_individual
            source = Ammitto::Sources::Un::Individual.from_hash(data)
            result = transformer.transform_individual(source)
          else
            source = Ammitto::Sources::Un::Entity.from_hash(data)
            result = transformer.transform_entity(source)
          end

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform US data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_us(transformer, data)
          guard_announcement_format!(:us, data, expected: 'Us::SdnEntry')

          sdn_entry = Ammitto::Sources::Us::SdnEntry.from_hash(data)
          result = transformer.transform(sdn_entry)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform WB data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_wb(transformer, data)
          firm = Ammitto::Sources::Wb::SanctionedFirm.from_hash(data)
          result = transformer.transform(firm)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform CA data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_ca(transformer, data)
          # Use Record class - it handles both individuals and entities
          # The YAML has given_name, not first_name
          source = Ammitto::Sources::Ca::Record.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Transform UN Vessels data
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Hash]
        def transform_un_vessels(transformer, data)
          source = Ammitto::Sources::UnVessels::Vessel.from_hash(data)
          result = transformer.transform(source)

          {
            entity: entity_to_hash(result[:entity]),
            entry: entry_to_hash(result[:entry])
          }
        end

        # Serializer producing the canonical camelCase JSON-LD shape
        # (@id/@type + context.jsonld terms). This is the single boundary
        # between harmonized models and every exported artifact — the exporters,
        # the search index, and the website all consume this vocabulary.
        # @return [Ammitto::Serialization::JsonLdSerializer]
        def json_ld_serializer
          @json_ld_serializer ||= Ammitto::Serialization::JsonLdSerializer.new
        end

        # Convert entity model to its canonical JSON-LD hash. Serialization
        # errors propagate to the per-file error collector — swallowing them
        # here would let the health gates count empty nodes as success.
        # @param entity [Object] entity model
        # @return [Hash, nil]
        def entity_to_hash(entity)
          return nil unless entity

          # Per-node @context is dropped; exporters add it at document level
          json_ld_serializer.serialize_entity(entity).except('@context')
        end

        # Convert entry model to its canonical JSON-LD hash (errors propagate)
        # @param entry [Object] entry model
        # @return [Hash, nil]
        def entry_to_hash(entry)
          return nil unless entry

          json_ld_serializer.serialize_entry(entry).except('@context')
        end
      end
    end
  end
end
