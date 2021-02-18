
require_relative "address"
require_relative "document_collection"

module Ammitto
  class SanctionItem
    attr_reader :names, :source, :entity_type, :country, :birthdate,
                :ref_number, :ref_type, :remark, :contact, :designation, :addresses, :documents


    def initialize(sanction_item)
      @names = sanction_item["names"] if sanction_item["names"].is_a?(Array)
      @source = sanction_item["source"] if sanction_item["source"].is_a?(String)
      @entity_type = sanction_item["entity_type"] if sanction_item["entity_type"].is_a?(String)
      @country = sanction_item["country"] if sanction_item["country"].is_a?(String)
      @birthdate = sanction_item["birthdate"] if sanction_item["birthdate"].is_a?(String)
      @ref_number = sanction_item["ref_number"].to_s if sanction_item["ref_number"].is_a?(String) || sanction_item["ref_number"].is_a?(Numeric)
      @ref_type = sanction_item["ref_type"] if sanction_item["ref_type"].is_a?(String)
      @remark = sanction_item["remark"] if sanction_item["remark"].is_a?(String)
      @contact = sanction_item["contact"] if sanction_item["contact"].is_a?(String)
      @designation = sanction_item["designation"] if sanction_item["designation"].is_a?(String)
      @addresses = sanction_item["address"].is_a?(Array) ? sanction_item["address"].map { |address| Ammitto::Address.new(address) } : []
      @documents = Ammitto::DocumentCollection.new(sanction_item["documents"] || [])
    end

    def to_hash
      hash = { }
      hash["names"] = names if names&.any?
      hash["source"] = source.to_s if source
      hash["entity_type"] = entity_type.to_s if entity_type
      hash["country"] = country.to_s if country
      hash["birthdate"] = birthdate.to_s if birthdate
      hash["ref_number"] = ref_number.to_s if birthdate
      hash["ref_type"] = ref_type.to_s if ref_type
      hash["remark"] = remark.to_s if remark
      hash["contact"] = contact.to_s if contact
      hash["designation"] = designation.to_s if designation
      hash["addresses"] = addresses.map(&:to_hash) if addresses&.any?
      hash["documents"] = documents.map(&:to_hash) if documents&.any?
      hash
    end

    def to_xml(**opts, &block)
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        render_xml builder: xml, **opts, &block
      end.doc.root.to_xml
    end

    private

    def render_xml(**opts)
      xml = opts[:builder].send(:sanction_item) do |builder|
        builder.names do
          names.each { |l| builder.name l }
        end
        builder.source source if source
        builder.entity_type entity_type if entity_type
        builder.country country if country
        builder.country country if country
        builder.birthdate birthdate if birthdate
        builder.ref_number ref_number if ref_number
        builder.ref_type ref_type if ref_type
        builder.remark remark if remark
        builder.contact contact if contact
        builder.designation designation if designation
        if addresses&.any?
          builder.addresses do |b|
            addresses.each { |address| address.to_xml(b) }
          end
        end
        if documents&.any?
          builder.documents do |b|
            documents.each { |document| document.to_xml(b) }
          end
        end
      end
      xml
    end

  end
end
