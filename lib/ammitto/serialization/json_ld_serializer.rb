# frozen_string_literal: true

require 'json'
require_relative '../schema/context'

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
          'hasSanctionEntry' => serialize_entry_ids(entity.sanction_entry_ids),
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
          'groupId' => entry.group_id,
          'legalCitations' => serialize_legal_citations(entry.legal_citations),
          'announcement' => serialize_announcement(entry.announcement),
          'rawSourceData' => serialize_raw_source_data(entry.raw_source_data)
        }.compact
      end

      # Serialize a complete document with entities and entries
      # @param entities [Array<Entity>] the entities
      # @param entries [Array<SanctionEntry>] the entries
      # @return [Hash] JSON-LD document
      def serialize_document(entities: [], entries: [])
        # Build a lookup map: entity_id => [entries] — one entity can carry
        # multiple sanction entries from different authorities
        entry_map = Hash.new { |h, k| h[k] = [] }
        entries.each do |entry|
          entry_map[entry.entity_id] << entry if entry.entity_id
        end

        graph = []

        entities.each do |entity|
          entity_hash = serialize_entity(entity)

          # Link entity to all of its SanctionEntries. The context declares
          # hasSanctionEntry as {'@type' => '@id', '@container' => '@set'},
          # so the value is always a set of entry IRIs — never an embedded
          # entry object and never a bare single value.
          linked = entry_map[entity.id].filter_map(&:id) if entry_map.key?(entity.id)
          merged = serialize_entry_ids((entity_hash['hasSanctionEntry'] || []) + (linked || []))
          entity_hash['hasSanctionEntry'] = merged if merged

          graph << entity_hash
        end

        # Every entry is a first-class node in the graph: entity nodes now
        # reference entries by IRI, so an embedded copy would leave the
        # referenced node undefined for anything but the orphan case.
        entries.each { |entry| graph << serialize_entry(entry) }

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
          'vesselTypeCode' => vessel.vessel_type_code,
          'buildYear' => vessel.build_year,
          'builder' => vessel.builder,
          'length' => vessel.length,
          'tonnage' => vessel.tonnage ? serialize_tonnage(vessel.tonnage) : nil,
          'grossTonnage' => vessel.gross_tonnage,
          'deadweightTonnage' => vessel.deadweight_tonnage,
          'owner' => vessel.owner ? serialize_entity_link(vessel.owner) : nil,
          'operator' => vessel.operator ? serialize_entity_link(vessel.operator) : nil,
          'registeredOwner' => vessel.registered_owner ? serialize_entity_link(vessel.registered_owner) : nil,
          'technicalManager' => vessel.technical_manager ? serialize_entity_link(vessel.technical_manager) : nil,
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

      # Entry IRIs an entity is linked to. Emitted under hasSanctionEntry,
      # which the context declares as {'@type' => '@id'}, so plain IRI
      # strings expand to node references — the same shape entityId
      # already uses for the inverse edge.
      # @param ids [Array<String>, nil] entry IRIs
      # @return [Array<String>, nil] deduplicated IRIs, or nil when empty
      def serialize_entry_ids(ids)
        return nil unless ids.is_a?(Array)

        cleaned = ids.filter_map do |id|
          next unless id.is_a?(String)

          stripped = id.strip
          stripped.empty? ? nil : stripped
        end.uniq
        cleaned.empty? ? nil : cleaned
      end

      # Legal citations on an entry. Term names follow the context's
      # LegalCitation block (legalInstrumentId/articles/sections/
      # paragraphs/citationType/context).
      # @param citations [Array, nil] LegalCitation models
      # @return [Array<Hash>, nil] citation nodes, or nil when none carry data
      def serialize_legal_citations(citations)
        return nil unless citations.is_a?(Array)

        nodes = citations.filter_map do |citation|
          node = {
            '@id' => citation.id,
            '@type' => 'LegalCitation',
            'legalInstrumentId' => citation.legal_instrument_id,
            'articles' => presence(citation.articles),
            'sections' => presence(citation.sections),
            'paragraphs' => presence(citation.paragraphs),
            'citationType' => citation.citation_type,
            'context' => citation.context,
            'quotedText' => presence(serialize_localized_strings(citation.quoted_text))
          }.compact
          node.keys == ['@type'] ? nil : node
        end

        nodes.empty? ? nil : nodes
      end

      # @param strings [Array, nil] LocalizedString models
      # @return [Array<Hash>, nil]
      def serialize_localized_strings(strings)
        return nil unless strings.is_a?(Array)

        strings.map do |string|
          {
            '@type' => 'LocalizedString',
            'value' => string.value,
            # 'lang', not 'language' — the context declares lang (schema/context.rb)
            'lang' => string.language,
            'script' => string.script,
            'region' => string.region,
            'isPrimary' => string.is_primary,
            'isTransliteration' => string.is_transliteration,
            'transliterationSystem' => string.transliteration_system
          }.compact
        end
      end

      # @param value [Array, nil] collection attribute
      # @return [Array, nil] the collection, or nil when empty
      def presence(value)
        value.nil? || value.empty? ? nil : value
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
            'publishDate' => base.publish_date,
            'url' => base.url,
            'lang' => base.lang
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
          'publishDate' => announcement.publish_date,
          'publishTime' => announcement.publish_time,
          'author' => announcement.author,
          'authorDate' => announcement.author_date,
          'documentType' => announcement.document_type,
          'documentId' => announcement.document_id,
          'signatory' => announcement.signatory,
          'signatoryTitle' => announcement.signatory_title,
          'publisher' => announcement.publisher,
          'authority' => announcement.authority,
          'content' => announcement.content,
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
