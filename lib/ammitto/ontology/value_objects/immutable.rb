# frozen_string_literal: true

require 'lutaml/model'
require 'date'
require 'stringio'

module Ammitto
  module Ontology
    module ValueObjects
      # Public value objects are sealed snapshots of their private hydration
      # models. Framework mapping setters never receive a sealed instance.
      module Immutable
        BORROWED_STATE = %i[@lutaml_register @lutaml_parent @lutaml_root @register_records].freeze
        OWNED_STATE = %i[@using_default @__order_tracking__ @ordered @mixed @mixed_content @element_order].freeze

        # Copies only declared domain fields and known serialization metadata.
        # Parent/register identities belong to the framework, not the value.
        def self.transfer(source, target, graph)
          attributes = source.class.attributes(source.lutaml_register)
          owned = attributes.keys.map { |key| :"@#{key}" } + OWNED_STATE
          unknown = source.instance_variables - owned - BORROWED_STATE
          raise ArgumentError, "Unsupported value-object state: #{unknown.join(', ')}" unless unknown.empty?

          source.instance_variables.each do |key|
            value = source.instance_variable_get(key)
            target.instance_variable_set(key, BORROWED_STATE.include?(key) ? value : graph.call(value))
          end
          target
        end
        private_class_method :transfer

        # One traversal owns its cycle state; no shared or thread-local bypass.
        class OwnedGraph
          ATOMS = [NilClass, TrueClass, FalseClass, Symbol, Integer, Float, Rational, Complex].freeze

          def initialize(seal:)
            @seal = seal
            @active = {}
          end

          def call(value)
            return value if ATOMS.any? { |kind| value.is_a?(kind) }
            # The missing-value sentinel is shared framework identity. It must
            # remain distinct from explicit nil, and we never freeze it globally.
            return value if value.is_a?(Lutaml::Model::UninitializedClass)
            return value if value.is_a?(Immutable) && value.frozen?

            key = value.object_id
            raise ArgumentError, 'Cyclic owned value graph' if @active.key?(key)

            @active[key] = true
            begin
              copied = copy(value)
              @seal ? copied.freeze : copied
            ensure
              @active.delete(key)
            end
          end

          private

          def copy(value)
            case value
            when String, Date, Time
              copied = value.dup
              copy_attached(value, copied)
            when Array then copy_attached(value, value.map { |child| call(child) })
            when Hash then copy_hash(value)
            when Lutaml::Model::Serializable then copy_model(value)
            else raise ArgumentError, "Unsupported owned value type: #{value.class}"
            end
          end

          def copy_hash(value)
            raise ArgumentError, 'Owned hashes cannot have a mutable default proc' if value.default_proc

            copied = value.dup.clear
            value.each { |key, child| copied[call(key)] = call(child) }
            copied.default = call(value.default)
            copy_attached(value, copied)
          end

          def copy_attached(value, copied)
            value.instance_variables.each { |key| copied.instance_variable_set(key, call(value.instance_variable_get(key))) }
            copied
          end

          def copy_model(value)
            # Mutable canonical instances are never a valid public input.
            raise ArgumentError, 'Unsealed canonical value object' if value.is_a?(Immutable)

            copied = value.class.new({}, register: value.lutaml_register)
            Immutable.send(:transfer, value, copied, self)
          end
        end
        private_constant :OwnedGraph

        # Lutaml's UTF-8 conversion duplicates strings without their attached
        # state. Keep that state owned while retaining native text conversion.
        module HydrationState
          def ensure_utf8(value)
            result = super
            return result unless value.is_a?(String) && result.is_a?(String) && !result.equal?(value)

            graph = OwnedGraph.new(seal: false)
            value.instance_variables.each { |key| result.instance_variable_set(key, graph.call(value.instance_variable_get(key))) }
            result
          end
        end
        private_constant :HydrationState

        def self.included(base)
          neo4j = base.respond_to?(:from_neo4j_record)
          base.superclass.extend(HydrationState)
          base.neo4j_labels(*base.superclass.all_neo4j_labels) if neo4j
          base.extend(ClassMethods)
          base.extend(Neo4jClassMethods) if neo4j
          base.private_class_method :allocate, :allocate_for_deserialization
        end

        module ClassMethods
          def new(attributes = {}, options = {}, &)
            copied = copy_attributes(attributes)
            project(hydration_model.new(copied, options.dup, &))
          end

          def from(format, data, options = {})
            project(hydration_model.from(format, parser_input(format, data), mapping_options(options)))
          end

          def of(format, data, options = {})
            project(hydration_model.of(format, OwnedGraph.new(seal: false).call(data), mapping_options(options)))
          end

          def apply_mappings(data, format, options = {})
            project(hydration_model.apply_mappings(OwnedGraph.new(seal: false).call(data), format, mapping_options(options)))
          end

          private

          def hydration_model
            model = superclass
            model = model.superclass while model.include?(Immutable)
            unless attribute_definition == attribute_definition(model) && mapping_definition == mapping_definition(model)
              raise ArgumentError, 'Value-object extensions must share a matching hydration definition'
            end

            model
          end

          def attribute_definition(model = self)
            model.attributes.transform_values { |attribute| [attribute.type, attribute.options] }
          end

          def mapping_definition(model = self)
            model.mappings.transform_values do |mapping|
              # Native MappingRule#deep_dup drops transforms. Compare actual
              # definition state so a changed import/export cannot bypass sealing.
              rules = mapping.mappings.map do |rule|
                # Native inheritance normalizes these constructor inputs;
                # @value_map retains their effective import/export semantics.
                keys = rule.instance_variables - %i[@treat_nil @treat_empty @treat_omitted]
                [rule.class, keys.to_h { |key| [key, rule.instance_variable_get(key)] }]
              end
              state = mapping.instance_variables - %i[@mappings @mappings_imported @finalized]
              [mapping.class, rules, state.to_h { |key| [key, mapping.instance_variable_get(key)] }]
            end
          end

          # YAML adapters natively borrow IO resources. Only parsed domain
          # state belongs to the value; the input stream stays caller-owned.
          def parser_input(format, data)
            return data if format.to_sym == :yaml && data.respond_to?(:read)

            OwnedGraph.new(seal: false).call(data)
          end

          def copy_attributes(attributes)
            graph = OwnedGraph.new(seal: false)
            attributes.to_h do |key, value|
              [key, key.to_s == 'lutaml_register' ? value : graph.call(value)]
            end
          end

          def mapping_options(options)
            copied = options.dup
            copied[:instance] = mutable_snapshot(options[:instance]) if options[:instance]
            copied
          end

          def mutable_snapshot(value)
            target = hydration_model.new({}, register: value.lutaml_register)
            Immutable.send(:transfer, value, target, OwnedGraph.new(seal: false))
          end

          def project(value)
            return value.map { |item| project(item) }.freeze if value.is_a?(Array)
            return nil if value.nil?

            target = allocate
            Immutable.send(:transfer, value, target, OwnedGraph.new(seal: true)).freeze
          end
        end
        private_constant :ClassMethods

        module Neo4jClassMethods
          def from_neo4j_record(record)
            value = hydration_model.from_neo4j_record(OwnedGraph.new(seal: false).call(record))
            value && project(value)
          end
        end
        private_constant :Neo4jClassMethods

        # Replacements retain default/missing flags for every untouched field.
        def with(**changes)
          unknown = changes.keys - self.class.attributes.keys
          raise ArgumentError, "Unknown value-object attributes: #{unknown.join(', ')}" unless unknown.empty?

          target = self.class.send(:mutable_snapshot, self)
          graph = OwnedGraph.new(seal: false)
          changes.each do |key, value|
            target.public_send(:"#{key}=", graph.call(value))
            target.value_set_for(key)
          end
          self.class.send(:project, target)
        end

        # Marshal restores without constructors or copy hooks. Restore only
        # known state through the same ownership boundary, then seal. Borrowed
        # parent/root references may form framework cycles and are not traversed.
        def marshal_dump
          instance_variables.to_h { |key| [key, instance_variable_get(key)] }
        end

        def marshal_load(state)
          source = self.class.send(:hydration_model).send(:allocate)
          state.each { |key, value| source.instance_variable_set(key, value) }
          Immutable.send(:transfer, source, self, OwnedGraph.new(seal: true))
          freeze
        end

        private

        def initialize_copy(original)
          super
          freeze
        end
      end
    end
  end
end
