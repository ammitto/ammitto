# frozen_string_literal: true

require 'json'

module Ammitto
  module Serialization
    # JsonLdSerializer serializes Ammitto models to JSON-LD format
    #
    # @example Serializing an entity
    #   serializer = Ammitto::Serialization::JsonLdSerializer.new
    #   json_ld = serializer.serialize_entity(entity)
    #
    # @example Serializing a sanction entry
    #   json_ld = serializer.serialize_entry(entry)
    #
    class JsonLdSerializer
      # Serialize an entity to JSON-LD
      # @param entity [Entity] the entity to serialize
      # @return [Hash] JSON-LD representation
      def serialize_entity(entity)
        {
          '@context' => Schema::Context.context_url,
          '@id' => entity.id,
          '@type' => type_for_entity(entity),
          'entityType' => entity.entity_type,
          'names' => serialize_names(entity.names),
          'sourceReferences' => serialize_source_references(entity.source_references),
          'linkedEntities' => serialize_linked_entities(entity.linked_entities),
          'sameAs' => entity.same_as,
          'remarks' => entity.remarks
        }.compact.merge(serialize_entity_specific(entity))
      end

      # Serialize a sanction entry to JSON-LD
      # @param entry [SanctionEntry] the entry to serialize
      # @return [Hash] JSON-LD representation
      def serialize_entry(entry)
        {
          '@context' => Schema::Context.context_url,
          '@id' => entry.id,
          '@type' => 'SanctionEntry',
          'entityId' => entry.entity_id,
          'authority' => serialize_authority(entry.authority),
          'regime' => serialize_regime(entry.regime),
          'listType' => serialize_list_type(entry.list_type),
          'legalBases' => serialize_legal_bases(entry.legal_bases),
          'effects' => serialize_effects(entry.effects),
          'reasons' => serialize_reasons(entry.reasons),
          'period' => serialize_period(entry.period),
          'status' => entry.status,
          'statusHistory' => serialize_status_history(entry.status_history),
          'referenceNumber' => entry.reference_number,
          'remarks' => entry.remarks,
          'announcement' => serialize_announcement(entry.announcement),
          'rawSourceData' => serialize_raw_source_data(entry.raw_source_data)
        }.compact
      end

      # Serialize a complete document with entities and entries
      # @param entities [Array<Entity>] the entities
      # @param entries [Array<SanctionEntry>] the entries
      # @return [Hash] JSON-LD document
      def serialize_document(entities: [], entries: [])
        # Build a lookup map: entity_id => entry
        entry_map = {}
        entries.each do |entry|
          entry_map[entry.entity_id] = entry if entry.entity_id
        end

        graph = []

        entities.each do |entity|
          entity_hash = serialize_entity(entity)

          # Link entity to its SanctionEntry
          entity_hash['hasSanctionEntry'] = serialize_entry(entry_map[entity.id]) if entry_map.key?(entity.id)

          graph << entity_hash
        end

        # Add orphan entries (entries without matching entities)
        entries.each do |entry|
          graph << serialize_entry(entry) unless entities.any? { |e| e.id == entry.entity_id }
        end

        {
          '@context' => Schema::Context.context_url,
          '@graph' => graph
        }
      end

      # Convert to JSON string
      # @param data [Hash] the data to convert
      # @return [String] JSON string
      def to_json(data)
        JSON.pretty_generate(data)
      end

      private

      def type_for_entity(entity)
        case entity
        when PersonEntity then 'PersonEntity'
        when OrganizationEntity then 'OrganizationEntity'
        when VesselEntity then 'VesselEntity'
        when AircraftEntity then 'AircraftEntity'
        else 'Entity'
        end
      end

      def serialize_entity_specific(entity)
        case entity
        when PersonEntity
          serialize_person_specific(entity)
        when OrganizationEntity
          serialize_organization_specific(entity)
        when VesselEntity
          serialize_vessel_specific(entity)
        when AircraftEntity
          serialize_aircraft_specific(entity)
        else
          {}
        end
      end

      def serialize_person_specific(person)
        {
          'birthInfo' => person.birth_info&.map { |b| serialize_birth_info(b) } || [],
          'deathDate' => person.death_date,
          'nationalities' => person.nationalities || [],
          'gender' => person.gender,
          'identifications' => person.identifications&.map { |i| serialize_identification(i) } || [],
          'addresses' => person.addresses&.map { |a| serialize_address(a) } || [],
          'title' => person.title,
          'position' => person.position,
          'affiliation' => person.affiliation
        }.compact
      end

      def serialize_organization_specific(org)
        {
          'registrationNumber' => org.registration_number,
          'incorporationDate' => org.incorporation_date,
          'dissolutionDate' => org.dissolution_date,
          'legalForm' => org.legal_form,
          'country' => org.country,
          'countryIsoCode' => org.country_iso_code,
          'identifications' => org.identifications&.map { |i| serialize_identification(i) } || [],
          'addresses' => org.addresses&.map { |a| serialize_address(a) } || [],
          'beneficialOwners' => org.beneficial_owners&.map { |b| serialize_entity_link(b) } || [],
          'website' => org.website,
          'sector' => org.sector
        }.compact
      end

      def serialize_vessel_specific(vessel)
        {
          'imoNumber' => vessel.imo_number,
          'mmsi' => vessel.mmsi,
          'callSign' => vessel.call_sign,
          'flagState' => vessel.flag_state,
          'flagStateIsoCode' => vessel.flag_state_iso_code,
          'vesselType' => vessel.vessel_type,
          'buildYear' => vessel.build_year,
          'tonnage' => vessel.tonnage ? serialize_tonnage(vessel.tonnage) : nil,
          'owner' => vessel.owner ? serialize_entity_link(vessel.owner) : nil,
          'operator' => vessel.operator ? serialize_entity_link(vessel.operator) : nil,
          'previousNames' => vessel.previous_names || [],
          'previousFlags' => vessel.previous_flags || []
        }.compact
      end

      def serialize_aircraft_specific(aircraft)
        {
          'serialNumber' => aircraft.serial_number,
          'manufacturer' => aircraft.manufacturer,
          'model' => aircraft.model,
          'registrationNumber' => aircraft.registration_number,
          'flagState' => aircraft.flag_state,
          'buildYear' => aircraft.build_year,
          'aircraftType' => aircraft.aircraft_type,
          'owner' => aircraft.owner ? serialize_entity_link(aircraft.owner) : nil,
          'operator' => aircraft.operator ? serialize_entity_link(aircraft.operator) : nil
        }.compact
      end

      def serialize_names(names)
        return [] unless names

        names.map do |name|
          {
            '@type' => 'NameVariant',
            'fullName' => name.full_name,
            'firstName' => name.first_name,
            'middleName' => name.middle_name,
            'lastName' => name.last_name,
            'script' => name.script,
            'language' => name.language,
            'isPrimary' => name.is_primary,
            'title' => name.title,
            'function' => name.function
          }.compact
        end
      end

      def serialize_birth_info(birth_info)
        {
          '@type' => 'BirthInfo',
          'date' => birth_info.date,
          'circa' => birth_info.circa,
          'year' => birth_info.year,
          'city' => birth_info.city,
          'region' => birth_info.region,
          'country' => birth_info.country,
          'countryIsoCode' => birth_info.country_iso_code
        }.compact
      end

      def serialize_address(address)
        return nil unless address

        {
          '@type' => 'Address',
          'street' => address.street,
          'city' => address.city,
          'state' => address.state,
          'country' => address.country,
          'countryIsoCode' => address.country_iso_code,
          'postalCode' => address.postal_code
        }.compact
      end

      def serialize_identification(id)
        {
          '@type' => 'Identification',
          'type' => id.type,
          'number' => id.number,
          'issuingCountry' => id.issuing_country,
          'countryIsoCode' => id.country_iso_code,
          'issueDate' => id.issue_date,
          'expiryDate' => id.expiry_date,
          'note' => id.note
        }.compact
      end

      def serialize_entity_link(link)
        return nil unless link

        {
          '@type' => 'EntityLink',
          'targetId' => link.target_id,
          'relationship' => link.relationship,
          'targetName' => link.target_name,
          'targetType' => link.target_type,
          'fromDate' => link.from_date,
          'toDate' => link.to_date
        }.compact
      end

      def serialize_source_references(refs)
        return [] unless refs

        refs.map do |ref|
          {
            '@type' => 'SourceReference',
            'sourceCode' => ref.source_code,
            'referenceNumber' => ref.reference_number,
            'url' => ref.url,
            'retrievedAt' => ref.retrieved_at
          }.compact
        end
      end

      def serialize_linked_entities(links)
        return [] unless links

        links.map { |l| serialize_entity_link(l) }
      end

      def serialize_authority(authority)
        return nil unless authority

        {
          '@type' => 'Authority',
          'id' => authority.id,
          'name' => authority.name,
          'countryCode' => authority.country_code,
          'url' => authority.url
        }.compact
      end

      def serialize_regime(regime)
        return nil unless regime

        {
          '@type' => 'SanctionRegime',
          'name' => regime.name,
          'code' => regime.code,
          'description' => regime.description
        }.compact
      end

      def serialize_list_type(list_type)
        return nil unless list_type

        {
          '@type' => 'ListType',
          'name' => list_type.name,
          'localizedName' => list_type.localized_name,
          'category' => list_type.category,
          'description' => list_type.description
        }.compact
      end

      def serialize_legal_bases(bases)
        return [] unless bases

        bases.map do |base|
          {
            '@type' => 'LegalInstrument',
            'type' => base.type,
            'identifier' => base.identifier,
            'title' => base.title,
            'issuingBody' => base.issuing_body,
            'issuanceDate' => base.issuance_date,
            'url' => base.url
          }.compact
        end
      end

      def serialize_effects(effects)
        return [] unless effects

        effects.map do |effect|
          {
            '@type' => 'SanctionEffect',
            'effectType' => effect.effect_type,
            'scope' => effect.scope,
            'description' => effect.description
          }.compact
        end
      end

      def serialize_reasons(reasons)
        return [] unless reasons

        reasons.map do |reason|
          {
            '@type' => 'SanctionReason',
            'category' => reason.category,
            'description' => reason.description,
            'citedProvisions' => reason.cited_provisions
          }.compact
        end
      end

      def serialize_period(period)
        return nil unless period

        {
          '@type' => 'TemporalPeriod',
          'listedDate' => period.listed_date,
          'effectiveDate' => period.effective_date,
          'expiryDate' => period.expiry_date,
          'isIndefinite' => period.is_indefinite,
          'lastUpdated' => period.last_updated
        }.compact
      end

      def serialize_status_history(history)
        return [] unless history

        history.map do |change|
          {
            '@type' => 'StatusChange',
            'date' => change.date,
            'fromStatus' => change.from_status,
            'toStatus' => change.to_status,
            'reason' => change.reason,
            'noticeReference' => serialize_notice_reference(change.notice_reference),
            'suspensionEndDate' => change.suspension_end_date
          }.compact
        end
      end

      def serialize_notice_reference(ref)
        return nil unless ref

        {
          '@type' => 'NoticeReference',
          'noticeNumber' => ref.notice_number,
          'noticeDate' => ref.notice_date,
          'noticeTitle' => ref.notice_title,
          'noticeUrl' => ref.notice_url
        }.compact
      end

      def serialize_announcement(announcement)
        return nil unless announcement

        {
          '@type' => 'OfficialAnnouncement',
          'title' => announcement.title,
          'url' => announcement.url,
          'publishedDate' => announcement.published_date,
          'author' => announcement.author,
          'authorDate' => announcement.author_date,
          'documentType' => announcement.document_type,
          'language' => announcement.language
        }.compact
      end

      def serialize_raw_source_data(data)
        return nil unless data

        {
          '@type' => 'RawSourceData',
          'sourceFile' => data.source_file,
          'sourceFormat' => data.source_format,
          'sourceXPath' => data.source_xpath,
          'rawContent' => data.raw_content,
          'sourceSpecificFields' => data.source_specific_fields
        }.compact
      end

      def serialize_tonnage(tonnage)
        return nil unless tonnage

        {
          '@type' => 'Tonnage',
          'grossRegisterTonnage' => tonnage.gross_register_tonnage,
          'grossTonnage' => tonnage.gross_tonnage,
          'deadweightTonnage' => tonnage.deadweight_tonnage,
          'netTonnage' => tonnage.net_tonnage
        }.compact
      end
    end
  end
end
