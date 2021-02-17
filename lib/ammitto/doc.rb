module Ammitto
  class Doc
    attr_reader :type, :number, :country, :note

    def initialize(doc)
      @type = doc["type"] if doc["type"].is_a?(String)
      @number = doc["number"] if doc["number"].is_a?(String)
      @country = doc["country"] if doc["country"].is_a?(String)
      @note = doc["note"] if doc["note"].is_a?(String)
    end

    def to_hash
      hash = {}
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
