# frozen_string_literal: true

module Ammitto
  module Sources
    module Uk
      # Non-Latin script name variant for UK designation
      #
      # Contains names in their original script (Arabic, Cyrillic, Chinese, etc.)
      #
      # @example
      #   name = Ammitto::Sources::Uk::NonLatinName.from_xml(xml)
      #   puts name.name_non_latin_script  # "حاجی خيرالله و حاجی ستار صرافی"
      #
      class NonLatinName < Lutaml::Model::Serializable
        attribute :name_non_latin_script, :string

        xml do
          root 'NonLatinName'
          map_element 'NameNonLatinScript', to: :name_non_latin_script
        end

        yaml do
          map 'name_non_latin_script', to: :name_non_latin_script
        end
      end
    end
  end
end
