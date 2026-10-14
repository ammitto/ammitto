# frozen_string_literal: true

module Ammitto
  module Ontology
    module Compatibility
      # Normalize comparison keys as well as values. Hash entries stay a
      # sequence, so equal normalized identity keys never overwrite each other.
      class Snapshot
        # Compare the normalized entry sequence as a multiset. Matching uses
        # Ruby equality directly, so neither encoding nor string formatting
        # changes the values, and equal identity entries retain multiplicity.
        class Entries < Array
          def ==(other)
            return false unless other.is_a?(Entries) && size == other.size

            remaining = other.to_a
            all? do |entry|
              index = remaining.index { |candidate| entry == candidate }
              next false unless index

              remaining.delete_at(index)
              true
            end
          end
        end
        private_constant :Entries

        def initialize(&model_snapshot)
          @model_snapshot = model_snapshot
          @active = {}
        end

        def call(value, key: false)
          id = value.object_id
          raise ConflictError, 'Cyclic compatibility snapshot' if @active.key?(id)

          @active[id] = true
          begin
            result = normalize(value, key)
            return result unless key

            kind = value.is_a?(Lutaml::Model::Serializable) ? 'model' : value.class.name
            [kind, result]
          ensure
            @active.delete(id)
          end
        end

        private

        def normalize(value, key)
          case value
          when Hash then hash_snapshot(value, key)
          when Array
            items = value.map { |item| call(item, key: key) }
            value.instance_variables.empty? ? items : { '@array' => items, 'state' => state(value) }
          when Lutaml::Model::Serializable then @model_snapshot.call(value, self)
          when String, Date, Time
            return value if value.instance_variables.empty?

            scalar = value.dup
            scalar.instance_variables.each { |name| scalar.remove_instance_variable(name) }
            { '@value' => scalar, 'type' => value.class.name, 'state' => state(value) }
          else value
          end
        end

        def hash_snapshot(value, key)
          raise ConflictError, 'Cannot snapshot a Hash default proc' if value.default_proc

          entries = value.map { |name, item| [call(name, key: true), call(item, key: key)] }
          { '@hash' => Entries.new(entries),
            'identity' => value.compare_by_identity?, 'default' => call(value.default), 'state' => state(value) }
        end

        def state(value)
          value.instance_variables.sort.to_h { |name| [name.to_s, call(value.instance_variable_get(name))] }
        end
      end
      private_constant :Snapshot
    end
  end
end
