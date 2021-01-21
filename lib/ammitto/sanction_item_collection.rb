# frozen_string_literal: true
require_relative 'sanction_item'
require 'forwardable'

module Ammitto
  class SanctionItemCollection
    extend Forwardable

    def_delegators :@array, :<<, :[], :first, :last, :empty?, :any?, :size,
                   :each, :detect, :map, :reduce, :length

    def initialize(collection)
      @array = collection.map { |si| SanctionItem.new(si) }
    end

  end
end
