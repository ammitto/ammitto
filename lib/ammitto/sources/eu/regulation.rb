# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Regulation (legal basis) for EU sanctions
      #
      # Example XML:
      # <regulation regulationType="regulation" organisationType="commission"
      #             publicationDate="2003-07-08" entryIntoForceDate="2003-07-07"
      #             numberTitle="1210/2003 (OJ L169)" programme="IRQ" logicalId="348">
      #   <publicationUrl>http://eur-lex.europa.eu/...</publicationUrl>
      # </regulation>
      class Regulation < Lutaml::Model::Serializable
        attribute :regulation_type, :string
        attribute :organisation_type, :string
        attribute :publication_date, :string
        attribute :entry_into_force_date, :string
        attribute :number_title, :string
        attribute :programme, :string
        attribute :logical_id, :string
        attribute :publication_url, :string

        xml do
          root 'regulation'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'regulationType', to: :regulation_type
          map_attribute 'organisationType', to: :organisation_type
          map_attribute 'publicationDate', to: :publication_date
          map_attribute 'entryIntoForceDate', to: :entry_into_force_date
          map_attribute 'numberTitle', to: :number_title
          map_attribute 'programme', to: :programme
          map_attribute 'logicalId', to: :logical_id
          map_element 'publicationUrl', to: :publication_url
        end

        yaml do
          map 'regulation_type', to: :regulation_type
          map 'organisation_type', to: :organisation_type
          map 'publication_date', to: :publication_date
          map 'entry_into_force_date', to: :entry_into_force_date
          map 'number_title', to: :number_title
          map 'programme', to: :programme
          map 'logical_id', to: :logical_id
          map 'publication_url', to: :publication_url
        end
      end
    end
  end
end
