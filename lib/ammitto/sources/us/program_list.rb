# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Program list wrapper
      class ProgramList < Lutaml::Model::Serializable
        attribute :programs, :string, collection: true

        xml do
          root 'programList'
          map_element 'program', to: :programs
        end

        yaml do
          map 'programs', to: :programs
        end
      end
    end
  end
end
