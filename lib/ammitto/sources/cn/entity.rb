# frozen_string_literal: true

require 'lutaml/model'
require_relative 'measure'

module Ammitto
  module Sources
    module Cn
      # Entity from YAML
      class Entity < Lutaml::Model::Serializable
        attribute :name, :hash # { 'zh-Hans' => '...', 'en' => '...' }
        attribute :type, :string # 'organization' or 'individual'
        attribute :effective_date, :string
        attribute :effective_time, :string
        attribute :sanction_list, :string
        attribute :reason, :hash, collection: true # [{ 'zh-Hans' => '...', 'en' => '...' }]
        attribute :measures, Measure, collection: true
        attribute :title, :hash # { 'zh-Hans' => '...', 'en' => '...' }
        attribute :gender, :string

        key_value do
          map 'name', to: :name
          map 'type', to: :type
          map 'effective_date', to: :effective_date
          map 'effective_time', to: :effective_time
          map 'sanction_list', to: :sanction_list
          map 'reason', to: :reason
          map 'measures', to: :measures
          map 'title', to: :title
          map 'gender', to: :gender
        end

        # Get Chinese name
        # @return [String, nil]
        def chinese_name
          name&.dig('zh-Hans')
        end

        # Get English name
        # @return [String, nil]
        def english_name
          name&.dig('en')
        end

        # Check if this is a person
        # @return [Boolean]
        def person?
          type == 'individual'
        end

        # Check if this is an organization
        # @return [Boolean]
        def organization?
          type == 'organization'
        end

        # Mapping of sanction_list values to list type codes. The data-cn
        # YAML stores source-prefixed slugs (e.g. "cn/anti-sanction-list")
        # while the schema enum documents the Chinese labels; both forms
        # must resolve to the same code so entries keep their list identity.
        LIST_TYPE_CODES = {
          '反制裁清单' => 'anti_sanctions',
          'anti-sanction-list' => 'anti_sanctions',
          '不可靠实体清单' => 'unreliable_entity',
          'unreliable-entity-list' => 'unreliable_entity',
          '出口管制管控名单' => 'export_control',
          'import-export-control-list' => 'export_control'
        }.freeze

        # Get list type code, accepting Chinese labels and data slugs
        # (with or without the "cn/" prefix)
        # @return [String]
        def list_type_code
          key = sanction_list.to_s.strip.delete_prefix('cn/')
          LIST_TYPE_CODES.fetch(key, 'unknown')
        end
      end
    end
  end
end
