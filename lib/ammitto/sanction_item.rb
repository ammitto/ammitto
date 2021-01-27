
require_relative "address"
require_relative "document"

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
      @ref_number = sanction_item["ref_number"] if sanction_item["ref_number"].is_a?(String)
      @ref_type = sanction_item["ref_type"] if sanction_item["ref_type"].is_a?(String)
      @remark = sanction_item["remark"] if sanction_item["remark"].is_a?(String)
      @contact = sanction_item["contact"] if sanction_item["contact"].is_a?(String)
      @designation = sanction_item["designation"] if sanction_item["designation"].is_a?(String)
      @addresses = sanction_item["address"].map { |address| Ammitto::Address.new(address) } if sanction_item["address"].is_a?(Array)
      @documents = sanction_item["documents"].map { |document| Ammitto::Document.new(document) } if sanction_item["documents"].is_a?(Array)
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

  end
end
