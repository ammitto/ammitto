# frozen_string_literal: true

require_relative '../../transformers/base_transformer'
require_relative 'subject_to'

module Ammitto
  module Sources
    module EuVessels
      # Transformer converts EU Vessels source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming an EU Vessel
      #   transformer = Ammitto::Sources::EuVessels::Transformer.new
      #   results = transformer.transform(vessel)
      #   results.first[:entity]      # VesselEntity
      #   results.map { |r| r[:entry] } # one SanctionEntry per designation
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:eu_vessels)
        end

        # Transform an EU Vessel to ontology models: one entity, and one
        # entry per designation DMA lists for it, since each row states its
        # own date, regulation and measure.
        #
        # The earliest designation keeps the entry IRI the vessel had when
        # the list carried one row per vessel, so existing links to it hold.
        # Later ones append their date and measure, which stay the same
        # when DMA adds rows, where a running index would renumber.
        #
        # One move remains possible, and it is accepted: if DMA adds a
        # designation dated before a vessel's current earliest, the new one
        # takes the bare IRI and the former earliest moves to its suffixed
        # IRI. Only a backdated row does that; a later row never moves one.
        #
        # @param vessel [Ammitto::Sources::EuVessels::Vessel] the vessel
        # @return [Array<Hash>] { entity: VesselEntity, entry: SanctionEntry }
        # @raise [Ammitto::ParseError] when the vessel has no designation or
        #   two designations would share an IRI, or when a vessel with more
        #   than one designation leaves a date or measure unstated
        def transform(vessel)
          designations = ordered_designations(vessel)

          entity = create_entity(vessel)
          results = designations.each_with_index.map do |designation, index|
            { entity: entity, entry: create_entry(vessel, entity, designation, first: index.zero?) }
          end

          shared = results.map { |r| r[:entry].id }.tally.select { |_, count| count > 1 }.keys
          raise Ammitto::ParseError, "eu_vessels: designations share entry IRI(s) #{shared.join(', ')}" if shared.any?

          results
        end

        # @param source_models [Array<Vessel>]
        # @return [Array<Hash>] every vessel's results, flattened
        def transform_all(source_models)
          source_models.flat_map { |model| transform(model) }
        end

        private

        # Designations ordered as the fetch merge orders them, because a
        # hand-edited or older YAML file need not list them earliest first.
        #
        # A later designation's IRI is built from its date and measure, and
        # sorting needs a date, so with several rows either one missing is
        # malformed input rather than something to publish.
        # @return [Array<Designation>]
        def ordered_designations(vessel)
          designations = vessel.designations_or_legacy
          raise Ammitto::ParseError, "eu_vessels: vessel #{vessel.local_id.inspect} has no designations" if designations.empty?
          return designations if designations.one?

          incomplete = designations.find { |d| d.date_of_application.nil? || d.subject_to.to_s.strip.empty? }
          if incomplete
            raise Ammitto::ParseError,
                  "eu_vessels: vessel #{vessel.local_id.inspect} has a designation without a date or " \
                  "\"Subject to\" value: #{[incomplete.date_of_application&.iso8601, incomplete.subject_to].inspect}"
          end

          designations.sort_by(&:sort_key)
        end

        # Create harmonized vessel entity
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [VesselEntity]
        def create_entity(vessel)
          Ammitto::VesselEntity.new.tap do |entity|
            entity.id = generate_entity_id(vessel.local_id)
            entity.entity_type = 'vessel'
            entity.names = build_names(vessel)
            entity.imo_number = vessel.imo_number
            entity.source_references = build_source_references(vessel)
          end
        end

        # Build names array
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [Array<NameVariant>]
        def build_names(vessel)
          names = []

          names << create_name_variant(full_name: vessel.vessel_name, is_primary: true) if vessel.vessel_name

          names
        end

        # Build source references
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [Array<SourceReference>]
        def build_source_references(vessel)
          [Ammitto::SourceReference.new(
            source_code: 'eu_vessels',
            reference_number: vessel.imo_number,
            retrieved_at: Time.now.utc.iso8601
          )]
        end

        # Create the sanction entry for one designation
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @param entity [VesselEntity] harmonized entity
        # @param designation [Ammitto::Sources::EuVessels::Designation]
        # @param first [Boolean] whether this is the vessel's earliest
        # @return [SanctionEntry]
        def create_entry(vessel, entity, designation, first:)
          subject_to = designation.subject_to && SubjectTo.parse(designation.subject_to)

          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(entry_local_id(vessel, designation, subject_to, first: first))
            entry.entity_id = entity.id
            entry.authority = authority
            entry.status = 'active'
            entry.period = Ammitto::TemporalPeriod.new(
              listed_date: designation.date_of_application,
              is_indefinite: true
            )
            state_measure(entry, subject_to, designation) if subject_to
          end
        end

        # A designation read from a file that predates the Subject to
        # column states no regime or measure, so its entry carries none.
        def state_measure(entry, subject_to, designation)
          entry.regime = Ammitto::SanctionRegime.new(**subject_to.regime)
          entry.legal_bases = [create_legal_basis(subject_to)]
          entry.effects = subject_to.effects.map { |effect| create_effect(**effect) }
          entry.remarks = designation.subject_to
        end

        # @return [String] the local part of the entry IRI
        def entry_local_id(vessel, designation, subject_to, first:)
          return vessel.local_id if first

          measure = subject_to.measures.join('-').downcase.gsub(/[^a-z0-9]+/, '-')
          "#{vessel.local_id}-#{designation.date_of_application&.iso8601}-#{measure}"
        end

        # @param subject_to [SubjectTo]
        # @return [LegalInstrument]
        def create_legal_basis(subject_to)
          Ammitto::LegalInstrument.new(
            type: 'regulation',
            identifier: subject_to.instrument[:identifier],
            title: subject_to.instrument[:identifier],
            issuing_body: 'Council of the European Union',
            url: subject_to.instrument[:url]
          )
        end
      end
    end
  end
end
