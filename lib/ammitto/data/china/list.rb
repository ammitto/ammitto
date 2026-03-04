# frozen_string_literal: true

require 'lutaml/model'
require_relative 'announcement'
require_relative 'entity'

module Ammitto
  module Data
    module China
      # Container for a sanctions list announcement with entities
      #
      # Represents a complete sanctions announcement from a Chinese government
      # source, including the announcement metadata and all affected entities.
      #
      # @example Load from YAML
      #   list = List.from_yaml(yaml_content)
      #   list.announcement.title # => "关于对...采取反制裁措施的决定"
      #   list.entities.count # => 3
      #   list.entities.first.names.first.value # => "余茂春"
      #
      class List < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :list_type, :string
        attribute :announcement, Announcement
        attribute :entities, Entity, collection: true
        attribute :instruments, :string, collection: true
        attribute :group_id, :string
        attribute :lang, :string, default: 'zh-Hans'

        yaml do
          root 'sanction_list'
          map 'id', to: :id
          map 'list_type', to: :list_type
          map 'announcement', to: :announcement
          map 'entities', to: :entities
          map 'instruments', to: :instruments
          map 'group_id', to: :group_id
          map 'lang', to: :lang
        end

        # Create from standard YAML file format
        # @param yaml_content [String] YAML content
        # @return [List]
        def self.from_yaml_file(yaml_content)
          data = YAML.safe_load(yaml_content, permitted_classes: [Date, Time], aliases: true)

          # Handle the standard announcement format
          if data['announcement'] && data['sanction_details']
            from_announcement_format(data)
          elsif data['measure_modifications']
            from_modification_format(data)
          else
            from_yaml(yaml_content)
          end
        end

        # Create from announcement format (sanction_details)
        # @param data [Hash] Parsed YAML data
        # @return [List]
        def self.from_announcement_format(data)
          list = new(
            id: data['id'],
            list_type: extract_list_type(data),
            group_id: data['group_id'],
            lang: data.dig('announcement', 'lang') || 'zh-Hans'
          )

          # Build announcement
          list.announcement = Announcement.new(
            id: data['id'],
            title: data.dig('announcement', 'title'),
            url: data.dig('announcement', 'url'),
            publish_date: parse_date(data.dig('announcement', 'publish_date')),
            publish_time: data.dig('announcement', 'publish_time'),
            document_id: data.dig('announcement', 'document_id'),
            document_type: data.dig('announcement', 'document_type'),
            authority: data.dig('announcement', 'authority'),
            publisher: data.dig('announcement', 'publisher'),
            signatory: data.dig('announcement', 'signatory'),
            signatory_title: data.dig('announcement', 'signatory_title'),
            content: data.dig('announcement', 'content'),
            lang: data.dig('announcement', 'lang') || 'zh-Hans'
          )

          # Build instruments
          list.instruments = data.dig('sanction_details', 'instruments')&.map do |inst|
            inst.is_a?(Hash) ? inst['id'] : inst
          end || []

          # Build entities from sanction_details
          list.entities = build_entities_from_details(data.dig('sanction_details', 'entities') || [],
                                                      data['sanction_details'],
                                                      data['announcement'],
                                                      data['id'])

          list
        end

        # Create from modification format (measure_modifications)
        # @param data [Hash] Parsed YAML data
        # @return [List]
        def self.from_modification_format(data)
          list = new(
            id: data['id'],
            list_type: 'modification',
            group_id: data['group_id'],
            lang: data.dig('announcement', 'lang') || 'zh-Hans'
          )

          list.announcement = Announcement.new(
            id: data['id'],
            title: data.dig('announcement', 'title'),
            url: data.dig('announcement', 'url'),
            publish_date: parse_date(data.dig('announcement', 'publish_date')),
            publish_time: data.dig('announcement', 'publish_time'),
            authority: data.dig('announcement', 'authority'),
            content: data.dig('announcement', 'content'),
            lang: data.dig('announcement', 'lang') || 'zh-Hans'
          )

          list.instruments = data.dig('measure_modifications', 'instruments')&.map do |inst|
            inst.is_a?(Hash) ? inst['id'] : inst
          end || []

          # Modification lists don't have entities, they reference existing ones
          list.entities = []

          list
        end

        # Extract list type from data
        # @param data [Hash] Parsed YAML data
        # @return [String]
        def self.extract_list_type(data)
          # Try to get from sanction_list field in entities
          first_entity = data.dig('sanction_details', 'entities', 0)
          list_name = first_entity&.dig('sanction_list')

          # Map Chinese names to list types
          LIST_TYPE_MAP[list_name] || 'unknown'
        end

        # Map Chinese list names to identifiers
        LIST_TYPE_MAP = {
          '反制裁清单' => 'anti-sanction-list',
          '不可靠实体清单' => 'unreliable-entity-list',
          '出口管制管控名单' => 'export-control-list',
          '对台军售实体' => 'taiwan-arms-sales'
        }.freeze

        # Build entities from sanction_details format
        # @param entities_data [Array<Hash>] Entity data
        # @param sanction_details [Hash] Sanction details
        # @param announcement [Hash] Announcement data
        # @param list_id [String] List ID
        # @return [Array<Entity>]
        def self.build_entities_from_details(entities_data, _sanction_details, _announcement, _list_id)
          entities_data.map.with_index do |entity_data, _index|
            Entity.new(
              type: entity_data['type'] || 'organization',
              names: build_names(entity_data['name']),
              gender: entity_data['gender'],
              title_zh: entity_data.dig('title', 'zh-Hans'),
              title_en: entity_data.dig('title', 'en'),
              measures: build_measures(entity_data['measures']),
              reasons: build_reasons(entity_data['reason']),
              effective_date: parse_date(entity_data['effective_date']),
              effective_time: entity_data['effective_time'],
              sanction_list: entity_data['sanction_list'],
              status: 'active'
            )
          end
        end

        # Build name objects from hash
        # @param name_data [Hash] Name data
        # @return [Array<Entity::Name>]
        def self.build_names(name_data)
          return [] unless name_data

          names = []
          name_data.each do |lang, value|
            next if lang == 'script' # Skip script metadata

            names << Entity::Name.new(
              value: value,
              lang: lang,
              script: name_data['script'] || (lang.start_with?('zh') ? 'Hani' : 'Latn'),
              is_primary: %w[zh-Hans en].include?(lang)
            )
          end

          # Mark first as primary if none marked
          names.first&.is_primary = true if names.none?(&:is_primary)

          names
        end

        # Build measure objects
        # @param measures_data [Array<Hash>] Measures data
        # @return [Array<Entity::Measure>]
        def self.build_measures(measures_data)
          return [] unless measures_data

          measures_data.map do |measure_data|
            Entity::Measure.new(
              type: Array(measure_data['type']).flatten,
              description_zh: measure_data['zh-Hans'],
              description_en: measure_data['en'],
              scope: 'full'
            )
          end
        end

        # Build reason objects
        # @param reasons_data [Array<Hash>] Reasons data
        # @return [Array<Entity::Reason>]
        def self.build_reasons(reasons_data)
          return [] unless reasons_data

          reasons_data.map do |reason_data|
            Entity::Reason.new(
              text_zh: reason_data['zh-Hans'],
              text_en: reason_data['en']
            )
          end
        end

        # Parse date from various formats
        # @param value [String, Date, nil] Date value
        # @return [Date, nil]
        def self.parse_date(value)
          return nil if value.nil?
          return value if value.is_a?(Date)

          Date.parse(value.to_s)
        rescue Date::Error
          nil
        end

        # Get entity count
        # @return [Integer]
        def entity_count
          entities.count
        end

        # Check if this is a modification (suspend/stop)
        # @return [Boolean]
        def modification?
          list_type == 'modification'
        end

        # Get list type slug for URLs
        # @return [String]
        def list_type_slug
          LIST_TYPE_MAP.invert[list_type] || list_type
        end
      end
    end
  end
end
