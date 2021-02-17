# frozen_string_literal: true
require 'forwardable'

require_relative 'passport'
require_relative 'national_id'
require_relative 'registration'
require_relative 'tax_id'
require_relative 'swift'
require_relative 'vat'
require_relative 'other'

module Ammitto
  class DocumentCollection
    extend Forwardable

    PASSPORT = ["Passport","Numéro de passeport","Número de pasaporte"]
    NATIONAL_ID = ["National Identification Number","National identification no."]
    REGISTRATION = ["License","Public Registration Number","Nationality of Registration", "Registration ID", "Business Registration Number", "Commercial Registry Number", "Registration Number" ]
    TAX_ID = ["Tax ID No."]
    SWIFT = ["SWIFT/BIC"]
    VAT = ["V.A.T. Number"]


    def_delegators :@array, :<<, :[], :first, :last, :empty?, :any?, :size,
                   :each, :detect, :map, :reduce, :length

    def initialize(collection)
      @array = collection.map do |doc|
        type = doc["type"]
        case
        when PASSPORT.include?(type)
          Passport.new(doc)
        when NATIONAL_ID.include?(type)
          NationalId.new(doc)
        when REGISTRATION.include?(type)
          Registration.new(doc)
        when TAX_ID.include?(type)
          TaxId.new(doc)
        when SWIFT.include?(type)
          Swift.new(doc)
        when VAT.include?(type)
          Vat.new(doc)
        else
          Other.new(doc)
        end

      end
    end

  end
end
