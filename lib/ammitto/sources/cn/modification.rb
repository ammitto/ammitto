# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Individual modification from YAML
      class Modification < Lutaml::Model::Serializable
        attribute :action, :string # 'suspend' or 'stop'
        attribute :target_announcement_id, :string
        attribute :target_announcement_date, :string
        attribute :effective_date, :string
        attribute :effective_time, :string
        attribute :until_date, :string
        attribute :until_time, :string
        attribute :duration_days, :integer
        attribute :affected_entity_names, :string, collection: true
        attribute :notes, :string

        key_value do
          map 'action', to: :action
          map 'target_announcement_id', to: :target_announcement_id
          map 'target_announcement_date', to: :target_announcement_date
          map 'effective_date', to: :effective_date
          map 'effective_time', to: :effective_time
          map 'until_date', to: :until_date
          map 'until_time', to: :until_time
          map 'duration_days', to: :duration_days
          map 'affected_entity_names', to: :affected_entity_names
          map 'notes', to: :notes
        end

        # Get affected entity count
        # @return [Integer]
        def affected_entity_count
          affected_entity_names&.size || 0
        end
      end
    end
  end
end
