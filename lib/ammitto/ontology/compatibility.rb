# frozen_string_literal: true

require 'lutaml/model'
require 'date'
require_relative '../error'
require_relative 'contracts'
require_relative 'compatibility/owned_graph'
require_relative 'compatibility/snapshot'

module Ammitto
  module Ontology
    # Lossless conversion between canonical ontology objects and their
    # legacy flat facades.
    #
    #   canonical = Compatibility.canonical(Ammitto::PersonEntity.new(...))
    #   flat      = Compatibility.legacy(canonical)
    #
    # Values move attribute by attribute, through the field names in
    # Contracts, never through to_hash, JSON or YAML: those drop fields
    # (NameVariant#to_hash omitted is_strong) and cast timestamps to dates.
    # Strings, arrays and hashes are copied, so the two graphs share no
    # mutable state and the caller's objects are left untouched.
    #
    # Every conversion is read back. A value the target cannot hold
    # exactly (a fractional vessel length on the Integer legacy field, an
    # entity_type a canonical subclass overrides) raises ConflictError
    # instead of being dropped or rounded.
    module Compatibility
      # A value has no lossless representation on the target side
      class ConflictError < Ammitto::Error; end

      # Legacy fields that were explicitly set to the value a canonical
      # entity subclass fixes anyway. The canonical object cannot record
      # that (its initializer always sets entity_type), so the flag rides
      # on the mutable canonical entity and goes back to the legacy side.
      EXPLICIT_LEGACY_FIELDS = :@compatibility_explicit_legacy_fields

      class << self
        # @param value [Object] a legacy facade object, a canonical object,
        #   or an Array/Hash of them
        # @return [Object] the canonical equivalent (a fresh deep copy)
        # @raise [ConflictError]
        def canonical(value)
          convert(value, :canonical)
        end

        # @param value [Object] a canonical object, a legacy object, or an
        #   Array/Hash of them
        # @return [Object] the legacy facade equivalent (a fresh deep copy)
        # @raise [ConflictError]
        def legacy(value)
          convert(value, :legacy)
        end

        # Facade-independent form of a value: fields keyed by their
        # canonical names, concept instead of class. Two objects with equal
        # snapshots carry the same data whichever facade they are on.
        #
        # @param flags [Boolean] include which fields still use their
        #   declared default (missing vs explicitly set)
        # @return [Object]
        def snapshot(value, flags: true)
          Snapshot.new { |model, graph| snapshot_object(model, flags, graph) }.call(value)
        end

        # @return [Boolean] whether +left+ and +right+ carry the same data
        def equivalent?(left, right)
          snapshot(left, flags: false) == snapshot(right, flags: false)
        end

        private

        def convert(value, side, graph = nil)
          graph ||= OwnedGraph.new { |model, owned| convert_object(model, side, owned) }
          graph.call(value)
        end

        def convert_object(source, side, active)
          chain = concept_chain(source.class)
          target_class = target_class_for(source.class, chain, side)
          fields = source.class.attributes.keys.to_h { |name| [name, target_field(chain, name, side)] }
          attributes = target_attributes(source, chain, fields, side, active)
          target = target_class.new(attributes)
          preserve_native_state(attributes, target, active)
          carry_state(source, target, chain, side, active)
          verify!(source, target, fields)
          target
        end

        # Native setters rebuild text and containers without owned metadata.
        # Canonical hydration preserves it before sealing; mutable facades
        # restore it after their normal native setters have run.
        def preserve_native_state(attributes, target, active)
          return if target.frozen?

          attributes.each do |key, value|
            next unless value.is_a?(String) || value.is_a?(Array) || value.is_a?(Hash)

            stored = target.public_send(key)
            active.copy_attached(value, stored) if stored.is_a?(value.class)
            stored.default = active.call(value.default) if value.is_a?(Hash) && stored.is_a?(Hash)
          end
        end

        # @return [Hash] constructor attributes for the target
        def target_attributes(source, chain, fields, side, active)
          source.class.attributes.each_with_object({}) do |(name, attribute), attributes|
            next if source.using_default?(name)

            value = source.public_send(name)
            next if value.nil? && !attribute.options.key?(:default)
            next if implied_by_subclass?(source, chain, fields[name], value, side)

            attributes[fields[name]] = convert(value, side, active)
          end
        end

        # A legacy entity subclass defaults entity_type to the value the
        # canonical subclass forces. Projecting that value back is only
        # right when the legacy object had it set explicitly.
        def implied_by_subclass?(source, chain, target_name, value, side)
          return false unless side == :legacy && chain.first&.last == :canonical

          default = chain.first.first.legacy_defaults[target_name]
          return false unless default && value == default

          !explicit_legacy_fields(source).include?(target_name)
        end

        def explicit_legacy_fields(object)
          return [] unless object.instance_variable_defined?(EXPLICIT_LEGACY_FIELDS)

          object.instance_variable_get(EXPLICIT_LEGACY_FIELDS)
        end

        def carry_state(source, target, chain, side, active)
          concept = chain.first&.first
          return unless concept

          concept.state.each do |ivar|
            next unless source.instance_variable_defined?(ivar)

            value = source.instance_variable_get(ivar)
            target.instance_variable_set(ivar, convert(value, side, active)) unless value.nil?
          end
          carry_explicit_flags(source, target, concept, side)
        end

        def carry_explicit_flags(source, target, concept, side)
          explicit =
            if chain_side(source) == :legacy && side == :canonical
              concept.legacy_defaults.keys.reject { |field| source.using_default?(field) }
            elsif side == :canonical
              explicit_legacy_fields(source)
            else
              []
            end
          target.instance_variable_set(EXPLICIT_LEGACY_FIELDS, explicit.dup.freeze) unless explicit.empty?
        end

        def chain_side(object)
          Contracts.lookup(object.class)&.last
        end

        # Read every field back from the target, including those left out
        # of the constructor: an initializer that derives a value (canonical
        # StatusHistory fills to_status from status) would otherwise add
        # data the source never had
        def verify!(source, target, fields)
          fields.each do |source_name, target_name|
            expected = snapshot(source.public_send(source_name), flags: false)
            actual = snapshot(target.public_send(target_name), flags: false)
            next if expected == actual

            raise ConflictError,
                  "#{source.class}##{source_name} -> #{target.class}##{target_name}: " \
                  "#{expected.inspect} cannot be represented (got #{actual.inspect})"
          end
        end

        # Concepts of +klass+ and of each registered ancestor, nearest first
        # @return [Array<Array(Contracts::Concept, Symbol)>]
        def concept_chain(klass)
          own = klass.ancestors.take_while { |ancestor| ancestor != Lutaml::Model::Serializable }
          own.grep(Class).filter_map { |ancestor| Contracts.lookup(ancestor) }
        end

        # Classes without a contract are copied only when they are the
        # ontology's own single definitions (LocalizedString, LegalCitation,
        # SanctionPeriodModification, ...); anything else, a source model
        # for instance, has no canonical form here and is refused.
        def target_class_for(klass, chain, side)
          concept, own_side = chain.first
          if concept.nil?
            return klass if klass.name&.start_with?('Ammitto::Ontology::')

            raise ConflictError, "#{klass} has no canonical/legacy contract"
          end
          raise ConflictError, "#{klass} has no contract of its own (#{concept.key} does)" unless Contracts.lookup(klass)
          return klass if own_side == side

          side == :canonical ? concept.canonical_class : concept.legacy_class
        end

        # Field name on +side+ for a source attribute, from the nearest
        # concept in the chain that renames it
        def target_field(chain, name, side)
          return name if chain.empty?

          own_side = chain.first.last
          return name if own_side == side

          chain.map(&:first).each do |concept|
            mapped = side == :canonical ? concept.canonical_field(name) : concept.legacy_field(name)
            return mapped unless mapped == name
          end
          name
        end

        def canonical_name(chain, name)
          return name if chain.empty? || chain.first.last == :canonical

          target_field(chain, name, :canonical)
        end

        def snapshot_object(object, flags, graph)
          chain = concept_chain(object.class)
          names = object.class.attributes.keys
          fields = names.to_h { |name| [canonical_name(chain, name).to_s, graph.call(object.public_send(name))] }
          result = { '@type' => chain.first ? chain.first.first.key.to_s : object.class.name,
                     'fields' => fields.sort.to_h }
          if flags
            result['defaults'] = names.select { |name| object.using_default?(name) }
                                      .map { |name| canonical_name(chain, name).to_s }.sort
          end
          state = snapshot_state(object, chain, graph)
          result['state'] = state unless state.empty?
          result
        end

        def snapshot_state(object, chain, graph)
          concept = chain.first&.first
          return {} unless concept

          concept.state.each_with_object({}) do |ivar, state|
            next unless object.instance_variable_defined?(ivar)

            value = object.instance_variable_get(ivar)
            state[ivar.to_s] = graph.call(value) unless value.nil? || value == []
          end
        end
      end
    end
  end
end
