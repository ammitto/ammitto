# frozen_string_literal: true

require 'lutaml/model'
require_relative '../ontology/contracts'

module Ammitto
  module Serialization
    # A canonical model read under its flat facade's field names, the names
    # the published JSON-LD vocabulary is built from.
    #
    # No flat model is constructed: each read returns the canonical value
    # in an exact legacy scalar type where possible, with nested models viewed the
    # same way. Building the flat facade instead would push every value
    # through the facade's own types, and a value one of them cannot hold
    # (a fractional vessel length on the Integer flat field) would stop the
    # serializer although the canonical model holds it validly.
    #
    # Where the facade keeps a type of its own (Contracts legacy_types), a
    # value it holds exactly still publishes in that type, as it always
    # has: an integral length stays an integer. Any other value publishes
    # as the canonical value, never rounded.
    #
    # Read-only: a view has readers for the facade's fields and nothing else.
    class WireView
      # @param value [Object] a canonical model, an Array of values, or any
      #   other value
      # @return [Object] the value, with each canonical contract model viewed
      def self.wrap(value)
        case value
        when Array then value.map { |item| wrap(item) }
        when Lutaml::Model::Serializable
          contract = value.class.ancestors.grep(Class).filter_map { |klass| Ontology::Contracts.lookup(klass) }.first
          contract&.last == :canonical ? new(value) : value
        else value
        end
      end

      # @param model [Lutaml::Model::Serializable] a canonical contract model
      def initialize(model)
        @model = model
        own = model.class.ancestors.take_while { |ancestor| ancestor != Lutaml::Model::Serializable }
        # Contracts of the class and its registered ancestors, nearest first
        @concepts = own.grep(Class).filter_map { |klass| Ontology::Contracts.lookup(klass)&.first }
        @fields = @concepts.first.legacy_class.attributes
      end

      def method_missing(name, *args)
        return super unless args.empty? && @fields.key?(name)

        read(name)
      end

      def respond_to_missing?(name, include_private = false)
        @fields.key?(name) || super
      end

      private

      def read(legacy_name)
        canonical_name = canonical_field(legacy_name)
        value = @model.public_send(canonical_name)
        value = legacy_default(legacy_name) if value.nil?
        self.class.wrap(in_legacy_type(canonical_name, value))
      end

      # The nearest contract that renames the field decides, as
      # Ontology::Compatibility reads it
      def canonical_field(legacy_name)
        @concepts.each do |concept|
          mapped = concept.canonical_field(legacy_name)
          return mapped unless mapped == legacy_name
        end
        legacy_name
      end

      # A flat entity subclass defaults entity_type; nothing else differs
      def legacy_default(legacy_name)
        @concepts.each do |concept|
          return concept.legacy_defaults[legacy_name] if concept.legacy_defaults.key?(legacy_name)
        end
        nil
      end

      def in_legacy_type(canonical_name, value)
        concept = @concepts.find { |candidate| candidate.legacy_types.key?(canonical_name) }
        return value unless concept && !value.nil?

        cast = Lutaml::Model::Type.lookup(concept.legacy_types[canonical_name]).cast(value)
        cast == value ? cast : value
      end
    end
  end
end
