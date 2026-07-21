# frozen_string_literal: true

require 'lutaml/model'

require_relative 'export_namespace'

module Ammitto
  module Sources
    module Eu
      # Subject type (person/organization classification)
      #
      # Example XML:
      # <subjectType code="person" classificationCode="P"/>
      class SubjectType < Lutaml::Model::Serializable
        attribute :code, :string
        attribute :classification_code, :string

        xml do
          root 'subjectType'
          namespace ExportNamespace

          map_attribute 'code', to: :code
          map_attribute 'classificationCode', to: :classification_code
        end

        yaml do
          map 'code', to: :code
          map 'classification_code', to: :classification_code
        end
      end
    end
  end
end
