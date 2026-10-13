# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Vessel details block of an SDN entry
      #
      # Example XML:
      # <vesselInfo>
      #   <callSign>CL2192</callSign>
      #   <vesselType>Tug</vesselType>
      #   <vesselFlag>Cuba</vesselFlag>
      #   <vesselOwner>Samir de Navegacion S.A.</vesselOwner>
      #   <tonnage>2595</tonnage>
      #   <grossRegisteredTonnage>212</grossRegisteredTonnage>
      # </vesselInfo>
      class VesselInfo < Lutaml::Model::Serializable
        attribute :call_sign, :string
        attribute :vessel_type, :string
        attribute :vessel_flag, :string
        attribute :vessel_owner, :string
        attribute :tonnage, :string
        attribute :gross_registered_tonnage, :string

        xml do
          root 'vesselInfo'
          map_element 'callSign', to: :call_sign
          map_element 'vesselType', to: :vessel_type
          map_element 'vesselFlag', to: :vessel_flag
          map_element 'vesselOwner', to: :vessel_owner
          map_element 'tonnage', to: :tonnage
          map_element 'grossRegisteredTonnage', to: :gross_registered_tonnage
        end

        yaml do
          map 'call_sign', to: :call_sign
          map 'vessel_type', to: :vessel_type
          map 'vessel_flag', to: :vessel_flag
          map 'vessel_owner', to: :vessel_owner
          map 'tonnage', to: :tonnage
          map 'gross_registered_tonnage', to: :gross_registered_tonnage
        end
      end
    end
  end
end
