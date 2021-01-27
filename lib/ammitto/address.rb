module Ammitto
  class Address
    attr_reader :street, :city, :state, :country, :zip

    def initialize(address)
      @street = address["street"] if address["street"].is_a?(String)
      @city = address["city"] if address["city"].is_a?(String)
      @state = address["state"] if address["state"].is_a?(String)
      @country = address["country"] if address["country"].is_a?(String)
      @zip = address["zip"] if address["zip"].is_a?(String)
    end

    def to_hash
      hash = { }
      hash["street"] = street.to_s if street
      hash["city"] = city.to_s if city
      hash["state"] = state.to_s if state
      hash["country"] = country.to_s if country
      hash["zip"] = zip.to_s if zip
      hash
    end

    def to_xml(builder)
      builder.address do
        builder.street street if city
        builder.city city if city
        builder.state state if state
        builder.country country if country
        builder.zip zip if zip
      end
    end

  end
end
