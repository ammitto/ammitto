require_relative "hash"

module Ammitto
  class Address
    attr_reader :street, :city, :state, :country, :zip

    def initialize(address)
      address.symbolize_keys!
      @street = address[:street] if address[:street].is_a?(String)
      @city = address[:city] if address[:city].is_a?(String)
      @state = address[:state] if address[:state].is_a?(String)
      @country = address[:country] if address[:country].is_a?(String)
      @zip = address[:zip] if address[:zip].is_a?(String)
    end

  end
end
