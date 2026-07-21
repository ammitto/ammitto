# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Name alias (person/organization name) from EU sanctions
      #
      # Example XML:
      # <nameAlias firstName="Saddam" middleName="" lastName="Hussein Al-Tikriti"
      #            wholeName="Saddam Hussein Al-Tikriti" function="" gender="M"
      #            title="" nameLanguage="" strong="true" regulationLanguage="en"
      #            logicalId="17">
      #   <regulationSummary .../>
      # </nameAlias>
      class NameAlias < Lutaml::Model::Serializable
        attribute :first_name, :string
        attribute :middle_name, :string
        attribute :last_name, :string
        attribute :whole_name, :string
        attribute :function, :string
        attribute :gender, :string
        attribute :title, :string
        attribute :name_language, :string
        attribute :strong, :boolean
        attribute :regulation_language, :string
        attribute :logical_id, :string
        attribute :regulation_summaries, RegulationSummary, collection: true

        xml do
          root 'nameAlias'
          namespace 'http://eu.europa.ec/fpi/fsd/export', nil

          map_attribute 'firstName', to: :first_name
          map_attribute 'middleName', to: :middle_name
          map_attribute 'lastName', to: :last_name
          map_attribute 'wholeName', to: :whole_name
          map_attribute 'function', to: :function
          map_attribute 'gender', to: :gender
          map_attribute 'title', to: :title
          map_attribute 'nameLanguage', to: :name_language
          map_attribute 'strong', to: :strong
          map_attribute 'regulationLanguage', to: :regulation_language
          map_attribute 'logicalId', to: :logical_id
          map_element 'regulationSummary', to: :regulation_summaries
        end

        yaml do
          map 'first_name', to: :first_name
          map 'middle_name', to: :middle_name
          map 'last_name', to: :last_name
          map 'whole_name', to: :whole_name
          map 'function', to: :function
          map 'gender', to: :gender
          map 'title', to: :title
          map 'name_language', to: :name_language
          map 'strong', to: :strong
          map 'regulation_language', to: :regulation_language
          map 'logical_id', to: :logical_id
          map 'regulation_summaries', to: :regulation_summaries
        end
      end
    end
  end
end
