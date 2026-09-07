# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ru
      # A measure imposed by an announcement.
      #
      # `type` is a list because the schema allows several; every record in
      # data-ru today carries exactly one, `entry_ban`.
      class Measure < Lutaml::Model::Serializable
        attribute :type, :string, collection: true
        attribute :ru, :string
        attribute :en, :string

        key_value do
          map 'type', to: :type
          map 'ru', to: :ru
          map 'en', to: :en
        end

        # @return [String, nil] the Russian description
        def russian_description
          ru
        end

        # @return [String, nil] the English description
        def english_description
          en
        end
      end
    end
  end
end
