require_relative "hash"
require_relative "address"
require_relative "document"

module Ammitto
  class SanctionItem
    attr_reader :names, :source, :entity_type, :country, :birthdate,
                :ref_number, :ref_type, :remark, :contact, :designation, :addresses, :documents

    def initialize(sanction_item)
      sanction_item.symbolize_keys!
      @names = sanction_item[:names] if sanction_item[:names].is_a?(Array)
      @source = sanction_item[:source] if sanction_item[:source].is_a?(String)
      @entity_type = sanction_item[:entity_type] if sanction_item[:entity_type].is_a?(String)
      @country = sanction_item[:country] if sanction_item[:country].is_a?(String)
      @birthdate = sanction_item[:country] if sanction_item[:country].is_a?(String)
      @ref_number = sanction_item[:ref_number] if sanction_item[:ref_number].is_a?(String)
      @ref_type = sanction_item[:ref_type] if sanction_item[:ref_type].is_a?(String)
      @remark = sanction_item[:remark] if sanction_item[:remark].is_a?(String)
      @contact = sanction_item[:contact] if sanction_item[:contact].is_a?(String)
      @designation = sanction_item[:designation] if sanction_item[:designation].is_a?(String)
      @addresses = sanction_item[:address].map { |address| Ammitto::Address.new(address) } if sanction_item[:address].is_a?(Array)
      @documents = sanction_item[:documents].map { |document| Ammitto::Document.new(document) } if sanction_item[:documents].is_a?(Array)
    end
  end
end
