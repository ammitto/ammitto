# frozen_string_literal: true

module Ammitto
  module Ontology
    module Compatibility
      # One conversion owns one cycle traversal. Framework parents and
      # registers stay outside this graph; model fields enter via its callback.
      class OwnedGraph
        ATOMS = [NilClass, TrueClass, FalseClass, Symbol, Integer, Float, Rational, Complex].freeze

        def initialize(&model_builder)
          @model_builder = model_builder
          @active = {}
          @completed = {}
        end

        def call(value)
          return value if ATOMS.any? { |kind| value.is_a?(kind) }
          return value if value.is_a?(Lutaml::Model::UninitializedClass)

          key = value.object_id
          raise ConflictError, 'Cyclic owned compatibility graph' if @active.key?(key)

          model = value.is_a?(Lutaml::Model::Serializable)
          return @completed[key] if model && @completed.key?(key)

          @active[key] = true
          begin
            copied =
              case value
              when Array then copy_attached(value, value.map { |item| call(item) })
              when Hash then copy_hash(value)
              when Lutaml::Model::Serializable then @model_builder.call(value, self)
              when String, Date, Time then copy_attached(value, value.dup)
              else raise ConflictError, "Unsupported owned compatibility value: #{value.class}"
              end
            @completed[key] = copied if model
            copied
          ensure
            @active.delete(key)
          end
        end

        def copy_attached(source, target)
          source.instance_variables.each do |key|
            target.instance_variable_set(key, call(source.instance_variable_get(key)))
          end
          target
        end

        private

        def copy_hash(value)
          raise ConflictError, 'Owned compatibility hashes cannot have a mutable default proc' if value.default_proc

          copied = value.dup.clear
          value.each do |key, child|
            owned_key = call(key)
            owned_key.freeze if owned_key.is_a?(String) && !copied.compare_by_identity?
            copied[owned_key] = call(child)
          end
          copied.default = call(value.default)
          copy_attached(value, copied)
        end
      end
      private_constant :OwnedGraph
    end
  end
end
