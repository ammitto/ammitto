# frozen_string_literal: true

module Ammitto
  module Sources
    module Uk
      # Address for UK designation
      #
      # UK addresses are structured with up to 6 lines plus country.
      # AddressLine5 is typically the city, AddressLine6 is the state/province.
      #
      # @example
      #   address = Ammitto::Sources::Uk::Address.from_xml(xml)
      #   puts address.address_line1    # Street
      #   puts address.address_line5    # City
      #   puts address.address_line6    # State/Province
      #   puts address.address_country  # Country
      #
      class Address < Lutaml::Model::Serializable
        attribute :address_line1, :string
        attribute :address_line2, :string
        attribute :address_line3, :string
        attribute :address_line4, :string
        attribute :address_line5, :string
        attribute :address_line6, :string
        attribute :address_country, :string

        xml do
          root 'Address'

          map_element 'AddressLine1', to: :address_line1
          map_element 'AddressLine2', to: :address_line2
          map_element 'AddressLine3', to: :address_line3
          map_element 'AddressLine4', to: :address_line4
          map_element 'AddressLine5', to: :address_line5
          map_element 'AddressLine6', to: :address_line6
          map_element 'AddressCountry', to: :address_country
        end

        yaml do
          map 'address_line1', to: :address_line1
          map 'address_line2', to: :address_line2
          map 'address_line3', to: :address_line3
          map 'address_line4', to: :address_line4
          map 'address_line5', to: :address_line5
          map 'address_line6', to: :address_line6
          map 'address_country', to: :address_country
        end

        # Get street address (combines lines 1-4)
        # @return [String]
        def street
          [address_line1, address_line2, address_line3, address_line4]
            .compact
            .join(', ')
        end

        # Get city (typically AddressLine5)
        # @return [String, nil]
        def city
          address_line5
        end

        # Get state/province (typically AddressLine6)
        # @return [String, nil]
        def state
          address_line6
        end

        # Get country
        # @return [String, nil]
        def country
          address_country
        end

        # Format as single line
        # @return [String]
        def to_s
          [street, city, state, country].compact.reject(&:empty?).join(', ')
        end
      end
    end
  end
end
