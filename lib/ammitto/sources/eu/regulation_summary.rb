# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Regulation summary referenced within other elements
      #
      # Example XML:
      # <regulationSummary regulationType="regulation" publicationDate="2003-07-08"
      #                     numberTitle="1210/2003 (OJ L169)"
      #                     publicationUrl="http://eur-lex.europa.eu/..."/>
      class RegulationSummary < Lutaml::Model::Serializable
        attribute :regulation_type, :string
        attribute :publication_date, :string
        attribute :number_title, :string
        attribute :publication_url, :string

        xml do
          root 'regulationSummary'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'regulationType', to: :regulation_type
          map_attribute 'publicationDate', to: :publication_date
          map_attribute 'numberTitle', to: :number_title
          map_attribute 'publicationUrl', to: :publication_url
        end

        yaml do
          map 'regulation_type', to: :regulation_type
          map 'publication_date', to: :publication_date
          map 'number_title', to: :number_title
          map 'publication_url', to: :publication_url
        end
      end
    end
  end
end
