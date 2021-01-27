module Ammitto
  class Document
    attr_reader :type, :number, :country, :note

    def initialize(address)
      @type = address["type"] if address["type"].is_a?(String)
      @number = address["number"] if address["number"].is_a?(String)
      @country = address["country"] if address["country"].is_a?(String)
      @note = address["note"] if address["note"].is_a?(String)
    end

    def to_hash
      hash = { }
      hash["type"] = type.to_s if type
      hash["number"] = number.to_s if number
      hash["country"] = country.to_s if country
      hash["note"] = note.to_s if note
      hash
    end

    def to_xml(builder)
      builder.document do
        builder.type type if type
        builder.number number if number
        builder.country country if country
        builder.note note if note
      end
    end

  end
end
