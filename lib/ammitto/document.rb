require_relative "hash"

module Ammitto
  class Document
    attr_reader :type, :number, :country, :note

    def initialize(address)
      address.symbolize_keys!
      @type = address[:type] if address[:type].is_a?(String)
      @number = address[:number] if address[:number].is_a?(String)
      @country = address[:country] if address[:country].is_a?(String)
      @note = address[:note] if address[:note].is_a?(String)
    end

  end
end
