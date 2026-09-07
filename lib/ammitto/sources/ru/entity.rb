# frozen_string_literal: true

require 'lutaml/model'
require_relative 'measure'

module Ammitto
  module Sources
    module Ru
      # One sanctioned party inside an announcement.
      #
      # `name`, `title` and each `reason` are plain hashes keyed by language
      # — `ru` and `en` in this corpus — rather than typed pairs, so a third
      # language appearing upstream is carried rather than dropped. That is
      # the same choice `Sources::Cn::Entity` makes for `zh-Hans`/`en`.
      class Entity < Lutaml::Model::Serializable
        attribute :name, :hash
        attribute :type, :string
        attribute :nationality, :string
        attribute :title, :hash
        attribute :effective_date, :string
        attribute :sanction_list, :string
        attribute :reason, :hash, collection: true
        attribute :measures, Measure, collection: true

        key_value do
          map 'name', to: :name
          map 'type', to: :type
          map 'nationality', to: :nationality
          map 'title', to: :title
          map 'effective_date', to: :effective_date
          map 'sanction_list', to: :sanction_list
          map 'reason', to: :reason
          map 'measures', to: :measures
        end

        # @return [String, nil] the Cyrillic name
        def russian_name
          name&.dig('ru')
        end

        # @return [String, nil] the Latin-script name
        def english_name
          name&.dig('en')
        end

        # @return [Boolean]
        def person?
          type != 'organization'
        end

        # @return [Boolean]
        def organization?
          type == 'organization'
        end

        # Russian labels for the lists MID publishes, mapped to codes.
        #
        # Every one of the 2428 records in data-ru today reads
        # "черного списка" — the stop-list, in the genitive case the
        # announcements use. The other labels are the ones MID's own
        # wording uses for the same list, kept so a differently-inflected
        # phrase does not silently become `unknown`.
        LIST_TYPE_CODES = {
          'черного списка' => 'stop_list',
          'чёрного списка' => 'stop_list',
          'черный список' => 'stop_list',
          'стоп-лист' => 'stop_list',
          'stop-list' => 'stop_list'
        }.freeze

        # @return [String] the list code, or 'unknown'
        def list_type_code
          key = sanction_list.to_s.strip.downcase.delete_prefix('ru/')
          LIST_TYPE_CODES.fetch(key, 'unknown')
        end
      end
    end
  end
end
