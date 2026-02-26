# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Publish information (metadata)
      class PublishInformation < Lutaml::Model::Serializable
        attribute :publish_date, :string
        attribute :record_count, :integer

        xml do
          root 'publshInformation'
          map_element 'Publish_Date', to: :publish_date
          map_element 'Record_Count', to: :record_count
        end

        yaml do
          map 'publish_date', to: :publish_date
          map 'record_count', to: :record_count
        end
      end
    end
  end
end
