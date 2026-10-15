# frozen_string_literal: true

module Ammitto
  module Transformers
    # Builds canonical ontology models for transformers, and declares which
    # transform methods return them.
    #
    # A transformer names models by their flat class and the flat keyword
    # arguments it has always used (Ammitto::PersonEntity, names:, ...).
    # .build renames those arguments through Ontology::Contracts and
    # constructs the paired canonical class directly: no flat object is
    # built and converted, and values never pass through to_hash or JSON.
    #
    # A source whose transformer calls .canonical_entrypoints keeps one
    # implementation per entrypoint. canonical_<name> runs it with every
    # model built canonical; <name> keeps the legacy flat API as an
    # explicit projection of that result through
    # Ontology::Compatibility.legacy. An entrypoint reached from inside a
    # canonical call (UN #transform dispatching to #transform_individual)
    # returns its canonical result as is.
    module CanonicalModels
      module_function

      # @param legacy_class [Class] the flat facade class the transformer names
      # @param attributes [Hash] the flat constructor's keyword arguments
      # @return [Lutaml::Model::Serializable] the canonical model
      def build(legacy_class, **attributes)
        concept, side = Ontology::Contracts.lookup(legacy_class)
        raise Ammitto::ConfigurationError, "#{legacy_class} has no canonical contract" unless side == :legacy

        model = concept.canonical_class.new(attributes.transform_keys { |name| concept.canonical_field(name) })
        # A canonical entity subclass fixes entity_type itself; an explicit
        # legacy value is recorded where Compatibility.legacy reads it, so
        # the flat projection keeps it explicit (entities are mutable)
        explicit = concept.legacy_defaults.keys & attributes.keys
        model.instance_variable_set(Ontology::Compatibility::EXPLICIT_LEGACY_FIELDS, explicit.freeze) if explicit.any?
        model
      end

      # Class-level declaration for a transformer
      module Entrypoints
        # @return [Boolean] whether this transformer builds canonical models
        def canonical?
          !canonical_entrypoint_names.empty?
        end

        # @return [Array<Symbol>]
        def canonical_entrypoint_names
          inherited = superclass.respond_to?(:canonical_entrypoint_names) ? superclass.canonical_entrypoint_names : []
          inherited | own_canonical_entrypoint_names
        end

        # Turns each named method into canonical_<name>, which runs the one
        # implementation building canonical models, plus <name>, its legacy
        # projection.
        # @param names [Array<Symbol>]
        # @return [void]
        def canonical_entrypoints(*names)
          names.each do |name|
            implementation = :"transform_implementation_#{name}"
            alias_method implementation, name
            private implementation
            define_method(:"canonical_#{name}") do |*args, **options, &block|
              building_canonical { send(implementation, *args, **options, &block) }
            end
            define_method(name) do |*args, **options, &block|
              result = public_send(:"canonical_#{name}", *args, **options, &block)
              building_canonical? ? result : Ontology::Compatibility.legacy(result)
            end
            own_canonical_entrypoint_names << name
          end
        end

        private

        def own_canonical_entrypoint_names
          @own_canonical_entrypoint_names ||= []
        end
      end

      # Instance side: whether models are being built canonical right now
      module Building
        private

        def building_canonical?
          @building_canonical == true
        end

        def building_canonical
          was = @building_canonical
          @building_canonical = true
          yield
        ensure
          @building_canonical = was
        end
      end
    end
  end
end
