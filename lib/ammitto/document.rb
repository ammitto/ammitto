module Ammitto
  class Document
    attr_reader :type, :number, :country, :note, :doc_name

    def initialize(doc)
      @type = doc["type"] if doc["type"].is_a?(String)
      @number = doc["number"] if doc["number"].is_a?(String)
      @country = doc["country"] if doc["country"].is_a?(String)
      @note = doc["note"] if doc["note"].is_a?(String)
    end


    def to_hash
      res = {}
      doc_name = self.class.to_s.sub('Ammitto::','').downcase
      res[doc_name] = {}
      res[doc_name]["type"] = type.to_s if type
      res[doc_name]["number"] = number.to_s if number
      res[doc_name]["country"] = country.to_s if country
      res[doc_name]["note"] = note.to_s if note
      res
    end

    def to_xml(builder)
      doc_name = self.class.to_s.sub('Ammitto::','').downcase
      builder.send(doc_name) do
        builder.type type if type
        builder.number number if number
        builder.country country if country
        builder.note note if note
      end
    end

  end
end
