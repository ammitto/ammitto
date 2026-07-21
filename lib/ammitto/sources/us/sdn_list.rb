# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Root element of US OFAC SDN list
      #
      # Example XML:
      # <sdnList xmlns="...">
      #   <publshInformation>...</publshInformation>
      #   <sdnEntry>...</sdnEntry>
      # </sdnList>
      class SdnList < Lutaml::Model::Serializable
        attribute :publish_information, PublishInformation
        attribute :entries, SdnEntry, collection: true

        xml do
          root 'sdnList'
          namespace 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/XML', nil

          map_element 'publshInformation', to: :publish_information
          map_element 'sdnEntry', to: :entries
        end

        yaml do
          map 'publish_information', to: :publish_information
          map 'entries', to: :entries
        end

        # Helper methods
        def publish_date
          publish_information&.publish_date
        end

        def record_count
          publish_information&.record_count || entries.count
        end

        def individuals
          entries.select { |e| e.entity_type == 'person' }
        end

        def organizations
          entries.select { |e| e.entity_type == 'organization' }
        end

        def vessels
          entries.select { |e| e.entity_type == 'vessel' }
        end

        def aircraft
          entries.select { |e| e.entity_type == 'aircraft' }
        end
      end
    end
  end
end
