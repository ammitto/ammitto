# frozen_string_literal: true

require 'lutaml/model'

require_relative 'export_namespace'

module Ammitto
  module Sources
    module Eu
      # One contact detail attached to an address in the EU list
      #
      # Example XML:
      # <contactInfo key="PHONE" value="262 38 18-19"/>
      #
      # The key is one of EMAIL, FAX, PHONE or WEB. The harmonized model
      # has no per-address contact field, so these live in the processed
      # YAML only.
      class ContactInfo < Lutaml::Model::Serializable
        attribute :key, :string
        attribute :value, :string

        xml do
          root 'contactInfo'
          namespace ExportNamespace

          map_attribute 'key', to: :key
          map_attribute 'value', to: :value
        end

        yaml do
          map 'key', to: :key
          map 'value', to: :value
        end
      end
    end
  end
end
