# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    # One contract per domain concept, pairing the canonical ontology class
    # with its legacy flat facade.
    #
    # The canonical class's Lutaml attributes are the only field
    # definitions: name, type, collection and default live there and nowhere
    # else. A legacy flat class declares its attributes by projecting them
    # (#declare_legacy_attributes), so the two facades cannot drift apart.
    # A concept records only what the projection needs on top of that:
    #
    # renames::         canonical field => legacy field, where the two
    #                   facades spell one fact differently (fetched_at /
    #                   retrieved_at) or where both shapes of a conflicting
    #                   field must survive (a String description and a
    #                   LocalizedString collection each get their own field).
    # legacy_types::    canonical field => Lutaml type the legacy facade
    #                   keeps (VesselEntity length stays an Integer there).
    # legacy_defaults:: legacy field => default a flat subclass redeclares
    #                   (each flat entity subclass defaults entity_type).
    # legacy_order::    the order the flat facade has always declared its
    #                   own fields in, where it differs from the canonical
    #                   order. Names only: a flat class without a YAML
    #                   mapping serializes in declaration order, so this
    #                   keeps its YAML byte-identical.
    # state::           instance variables outside Lutaml attributes that a
    #                   conversion must carry (an entity's sanction entries).
    #
    # Class names are strings so this file loads before any model.
    module Contracts
      # Pairing and projection rules for one concept
      class Concept
        attr_reader :key, :canonical_name, :legacy_name, :renames,
                    :legacy_types, :legacy_defaults, :legacy_order, :state

        def initialize(key, canonical:, legacy:, renames: {}, legacy_types: {},
                       legacy_defaults: {}, legacy_order: [], state: [])
          @key = key
          @canonical_name = canonical
          @legacy_name = legacy
          @renames = renames.freeze
          @inverse_renames = renames.invert.freeze
          @legacy_types = legacy_types.freeze
          @legacy_defaults = legacy_defaults.freeze
          @legacy_order = legacy_order.freeze
          @state = state.freeze
          freeze
        end

        # @return [Class] the canonical ontology class
        def canonical_class
          Object.const_get(canonical_name)
        end

        # @return [Class] the legacy flat facade class
        def legacy_class
          Object.const_get(legacy_name)
        end

        # @param canonical_field [Symbol]
        # @return [Symbol] the legacy facade's name for the field
        def legacy_field(canonical_field)
          renames.fetch(canonical_field, canonical_field)
        end

        # @param legacy_field [Symbol]
        # @return [Symbol] the canonical name for a legacy field
        def canonical_field(legacy_field)
          @inverse_renames.fetch(legacy_field, legacy_field)
        end

        # Canonical field names in the order the legacy facade declares
        # them: a subclass's own default first (where the flat subclass has
        # always redeclared it), then legacy_order, then the rest in
        # canonical order
        # @return [Array<Symbol>]
        def legacy_declaration_order
          first = (legacy_defaults.keys + legacy_order).map { |field| canonical_field(field) }.uniq
          first + (canonical_class.attributes.keys - first)
        end
      end

      @registry = {}

      class << self
        # @return [Hash{Symbol => Concept}]
        def registry
          @registry.dup.freeze
        end

        # Register a concept
        # @return [Concept]
        def define(key, **)
          raise ArgumentError, "concept #{key} already defined" if @registry.key?(key)

          @registry[key] = Concept.new(key, **)
        end

        # @param key [Symbol]
        # @return [Concept]
        def fetch(key)
          @registry.fetch(key)
        end

        # The concept a class belongs to, on either side.
        # @param klass [Class]
        # @return [Array(Concept, Symbol), nil] the concept and the side
        #   (:canonical or :legacy) +klass+ is on; nil for classes that have
        #   a single definition shared by both facades (LocalizedString)
        def lookup(klass)
          name = klass.name
          @registry.each_value do |concept|
            return [concept, :canonical] if concept.canonical_name == name
            return [concept, :legacy] if concept.legacy_name == name
          end
          nil
        end

        # Declare a legacy flat class's attributes from its canonical
        # class. Fields the flat superclass already declares are inherited,
        # not redeclared, unless the concept gives the subclass its own
        # default.
        #
        # @param klass [Class] the legacy flat class being defined
        # @return [void]
        def declare_legacy_attributes(klass)
          concept, side = lookup(klass)
          raise ArgumentError, "#{klass} is not a legacy facade" unless side == :legacy

          inherited = klass.superclass.respond_to?(:attributes) ? klass.superclass.attributes : {}
          canonical = concept.canonical_class.attributes
          concept.legacy_declaration_order.each do |name|
            attribute = canonical.fetch(name)
            legacy = concept.legacy_field(name)
            next if inherited.key?(legacy) && !concept.legacy_defaults.key?(legacy)

            klass.attribute(legacy, legacy_type(concept, name, attribute),
                            **legacy_options(concept, legacy, attribute))
          end
        end

        # @return [Class] the class +type+ is paired with on +side+, or
        #   +type+ itself for primitives and shared single-definition classes
        def paired_class(type, side)
          return type unless type.is_a?(Class) && type <= Lutaml::Model::Serializable

          concept, = lookup(type)
          return type unless concept

          side == :legacy ? concept.legacy_class : concept.canonical_class
        end

        private

        def legacy_type(concept, name, attribute)
          return concept.legacy_types[name] if concept.legacy_types.key?(name)

          paired_class(attribute.type, :legacy)
        end

        def legacy_options(concept, legacy, attribute)
          options = attribute.options.slice(:collection, :default)
          options[:default] = concept.legacy_defaults[legacy] if concept.legacy_defaults.key?(legacy)
          options
        end
      end

      VO = 'Ammitto::Ontology::ValueObjects'
      ENTITIES = 'Ammitto::Ontology::Entities'
      SANCTION = 'Ammitto::Ontology::Sanction'
      ENTITY_STATE = %i[@sanction_entries @explicit_authority].freeze
      private_constant :VO, :ENTITIES, :SANCTION, :ENTITY_STATE

      define :name_variant, canonical: "#{VO}::NameVariant", legacy: 'Ammitto::NameVariant',
                            legacy_order: %i[full_name first_name middle_name last_name script language
                                             is_primary title function]
      define :address, canonical: "#{VO}::Address", legacy: 'Ammitto::Address'
      define :identification, canonical: "#{VO}::Identification", legacy: 'Ammitto::Identification',
                              legacy_order: %i[type number issuing_country country_iso_code issue_date
                                               expiry_date note]
      define :birth_info, canonical: "#{VO}::BirthInfo", legacy: 'Ammitto::BirthInfo'
      define :legal_instrument, canonical: "#{VO}::LegalInstrument", legacy: 'Ammitto::LegalInstrument'
      define :sanction_effect, canonical: "#{VO}::SanctionEffect", legacy: 'Ammitto::SanctionEffect',
                               renames: { description: :description_text,
                                          localized_descriptions: :description }
      define :temporal_period, canonical: "#{VO}::TemporalPeriod", legacy: 'Ammitto::TemporalPeriod',
                               renames: { last_updated: :last_updated_date,
                                          last_updated_timestamp: :last_updated }
      define :contact_info, canonical: "#{VO}::ContactInfo", legacy: 'Ammitto::ContactInfo',
                            legacy_order: %i[phone fax email website note]
      define :entity_link, canonical: "#{VO}::EntityLink", legacy: 'Ammitto::EntityLink',
                           renames: { relationship_type: :relationship }
      define :source_reference, canonical: "#{VO}::SourceReference", legacy: 'Ammitto::SourceReference',
                                renames: { fetched_at: :retrieved_at }
      define :tonnage, canonical: "#{VO}::Tonnage", legacy: 'Ammitto::Tonnage',
                       renames: { gt: :gross_tonnage, dwt: :deadweight_tonnage,
                                  nt: :net_tonnage, grt: :gross_register_tonnage },
                       legacy_order: %i[gross_register_tonnage gross_tonnage deadweight_tonnage net_tonnage]
      define :notice_reference, canonical: "#{VO}::NoticeReference", legacy: 'Ammitto::NoticeReference'
      define :raw_source_data, canonical: "#{VO}::RawSourceData", legacy: 'Ammitto::RawSourceData'

      define :entity, canonical: "#{ENTITIES}::Entity", legacy: 'Ammitto::Entity', state: ENTITY_STATE
      define :person_entity, canonical: "#{ENTITIES}::PersonEntity", legacy: 'Ammitto::PersonEntity',
                             legacy_defaults: { entity_type: 'person' }, state: ENTITY_STATE
      define :organization_entity, canonical: "#{ENTITIES}::OrganizationEntity",
                                   legacy: 'Ammitto::OrganizationEntity',
                                   renames: { beneficial_owners: :beneficial_owner_names,
                                              beneficial_owner_links: :beneficial_owners },
                                   legacy_defaults: { entity_type: 'organization' }, state: ENTITY_STATE,
                                   legacy_order: %i[registration_number incorporation_date dissolution_date
                                                    legal_form country country_iso_code identifications
                                                    addresses contact_info beneficial_owners directors
                                                    parent_organization subsidiaries website sector]
      define :vessel_entity, canonical: "#{ENTITIES}::VesselEntity", legacy: 'Ammitto::VesselEntity',
                             renames: { mmsi_number: :mmsi, deadweight: :deadweight_tonnage,
                                        registered_owner: :registered_owner_name,
                                        registered_owner_link: :registered_owner,
                                        owner_link: :owner, operator_link: :operator },
                             legacy_types: { length: :integer },
                             legacy_defaults: { entity_type: 'vessel' }, state: ENTITY_STATE,
                             legacy_order: %i[imo_number mmsi call_sign flag_state flag_state_iso_code
                                              vessel_type vessel_type_code tonnage build_year builder length
                                              gross_tonnage deadweight_tonnage owner operator registered_owner
                                              technical_manager previous_names previous_flags]
      define :aircraft_entity, canonical: "#{ENTITIES}::AircraftEntity", legacy: 'Ammitto::AircraftEntity',
                               renames: { registration: :registration_number,
                                          registration_country: :flag_state,
                                          operator: :operator_name, operator_link: :operator,
                                          owner_link: :owner },
                               legacy_defaults: { entity_type: 'aircraft' }, state: ENTITY_STATE,
                               legacy_order: %i[serial_number manufacturer model registration_number flag_state
                                                flag_state_iso_code build_year aircraft_type engine_type owner
                                                operator previous_registrations]

      define :authority, canonical: "#{SANCTION}::Authority", legacy: 'Ammitto::Authority'
      define :sanction_regime, canonical: "#{SANCTION}::SanctionRegime", legacy: 'Ammitto::SanctionRegime',
                               legacy_order: %i[name code description]
      define :sanction_reason, canonical: "#{SANCTION}::SanctionReason", legacy: 'Ammitto::SanctionReason',
                               renames: { description: :description_text,
                                          localized_descriptions: :description }
      define :status_history, canonical: "#{SANCTION}::StatusHistory", legacy: 'Ammitto::StatusChange',
                              renames: { date: :change_date, timestamp: :date },
                              legacy_order: %i[date from_status to_status reason notice_reference
                                               suspension_end_date]
      define :list_type, canonical: "#{SANCTION}::ListType", legacy: 'Ammitto::ListType'
      define :official_announcement, canonical: "#{SANCTION}::OfficialAnnouncement",
                                     legacy: 'Ammitto::OfficialAnnouncement'
      define :sanction_entry, canonical: "#{SANCTION}::SanctionEntry", legacy: 'Ammitto::SanctionEntry',
                              renames: { list_type: :list_type_code, list_type_detail: :list_type,
                                         reasons: :reason_texts, reason_details: :reasons,
                                         announcement: :announcement_text,
                                         announcement_detail: :announcement,
                                         raw_source_data: :raw_source_hash,
                                         raw_source_detail: :raw_source_data },
                              legacy_order: %i[id entity_id authority regime list_type legal_bases effects reasons
                                               period status status_history modifications reference_number
                                               remarks announcement group_id legal_citations raw_source_data]
    end
  end
end
