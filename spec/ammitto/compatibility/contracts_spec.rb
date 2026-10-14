# frozen_string_literal: true

require 'spec_helper'
require 'json'

# Field ownership between the canonical ontology classes and their legacy
# flat facades. The oracle is base_model_inventory.json, captured from both
# public interfaces on the commit before the contracts existed, so these
# examples compare against what the classes were, not against the new code.
RSpec.describe 'Ammitto::Ontology::Contracts' do
  inventory_path = File.expand_path('../../fixtures/compatibility/base_model_inventory.json', __dir__)
  inventory = JSON.parse(File.read(inventory_path)).fetch('concepts')

  def self.concept_key(name)
    { 'StatusChange' => :status_history }.fetch(name) { name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym }
  end

  def describe_attribute(attribute)
    default = attribute.options[:default]
    default = default.call if default.is_a?(Proc)
    { 'type' => attribute.type.name, 'collection' => attribute.collection? == true,
      'default' => default.inspect }
  end

  let(:contracts) { Ammitto::Ontology::Contracts }

  it 'pairs every flat class with a canonical class, and nothing else' do
    expect(contracts.registry.keys).to match_array(inventory.keys.map { |name| self.class.concept_key(name) })
  end

  inventory.each do |name, sides|
    key = concept_key(name)

    describe name do
      let(:concept) { contracts.fetch(key) }

      sides.each do |side, captured|
        it "keeps every #{side} attribute the base commit declared, with its type, collection flag and default" do
          klass = Object.const_get(captured.fetch('class'))
          current = klass.attributes.transform_keys(&:to_s)
          captured.fetch('attributes').each do |field, expected|
            expect(current).to have_key(field), "#{klass}##{field} disappeared"
            expect(describe_attribute(current[field])).to eq(expected), "#{klass}##{field} changed"
          end
        end
      end

      # Without a YAML mapping a flat class serializes in declaration order
      it 'keeps the flat facade declaring its base fields in the base order' do
        base_order = sides.fetch('flat').fetch('attributes').keys
        current = concept.legacy_class.attributes.keys.map(&:to_s)
        expect(current & base_order).to eq(base_order)
      end

      it 'gives the canonical class a field for every base field of both facades' do
        canonical = concept.canonical_class.attributes
        sides.fetch('flat').fetch('attributes').each_key do |field|
          expect(canonical).to have_key(concept.canonical_field(field.to_sym)),
                               "flat #{name}##{field} has no canonical home"
        end
        sides.fetch('ontology', { 'attributes' => {} }).fetch('attributes').each_key do |field|
          expect(canonical).to have_key(field.to_sym)
        end
      end

      it 'declares the flat facade only as a projection of the canonical attributes' do
        legacy = concept.legacy_class.attributes
        canonical = concept.canonical_class.attributes
        expect(legacy.keys.map { |field| concept.canonical_field(field) }).to match_array(canonical.keys)
        legacy.each do |field, attribute|
          source = canonical.fetch(concept.canonical_field(field))
          expected_type = concept.legacy_types.fetch(concept.canonical_field(field)) do
            contracts.paired_class(source.type, :legacy)
          end
          expected_type = Lutaml::Model::Type.const_get(expected_type.to_s.capitalize) if expected_type.is_a?(Symbol)
          expect(attribute.type).to eq(expected_type), "#{concept.legacy_class}##{field}"
          expect(attribute.collection?).to eq(source.collection?)
        end
      end
    end
  end

  it 'leaves no hand-written attribute declaration in any flat facade file' do
    flat_files = contracts.registry.values.map do |concept|
      File.expand_path("../../../lib/ammitto/#{concept.legacy_name.split('::').last
        .gsub(/([a-z])([A-Z])/, '\1_\2').downcase}.rb", __dir__)
    end
    offenders = flat_files.select { |path| File.read(path).match?(/^\s*attribute\s+:/) }
    expect(offenders).to be_empty
  end

  describe 'distinctions the canonical model must keep' do
    def field(klass, name)
      attribute = klass.attributes.fetch(name)
      [attribute.type, attribute.collection?]
    end

    let(:vo) { Ammitto::Ontology::ValueObjects }
    let(:entities) { Ammitto::Ontology::Entities }
    let(:sanction) { Ammitto::Ontology::Sanction }
    let(:string) { Lutaml::Model::Type::String }

    it 'keeps street2, state and region apart on Address' do
      expect(%i[street street2 region state].map { |f| field(vo::Address, f) }).to all(eq([string, false]))
    end

    it 'keeps the identification country code and note' do
      expect([field(vo::Identification, :country_iso_code), field(vo::Identification, :note)])
        .to all(eq([string, false]))
    end

    it 'keeps raw listing/effective times and the raw last-update timestamp beside the dates' do
      expect(%i[listed_time effective_time last_updated_timestamp].map { |f| field(vo::TemporalPeriod, f) })
        .to all(eq([string, false]))
      expect(field(vo::TemporalPeriod, :last_updated)).to eq([Lutaml::Model::Type::Date, false])
    end

    it 'keeps LocalizedString collections apart from the scalar descriptions' do
      [vo::SanctionEffect, sanction::SanctionReason].each do |klass|
        expect(field(klass, :localized_descriptions)).to eq([vo::LocalizedString, true])
        expect(field(klass, :description)).to eq([string, false])
      end
    end

    it 'keeps the legal programme, language and the contact note' do
      expect([field(vo::LegalInstrument, :programme), field(vo::LegalInstrument, :lang),
              field(vo::ContactInfo, :note)]).to all(eq([string, false]))
    end

    it 'keeps rich entity links beside the name strings' do
      link = vo::EntityLink
      expect(field(entities::OrganizationEntity, :beneficial_owner_links)).to eq([link, true])
      expect(field(entities::OrganizationEntity, :beneficial_owners)).to eq([string, true])
      %i[owner_link operator_link registered_owner_link technical_manager].each do |f|
        expect(field(entities::VesselEntity, f)).to eq([link, false])
      end
      expect(field(entities::AircraftEntity, :operator_link)).to eq([link, false])
      expect(field(entities::AircraftEntity, :operator)).to eq([string, false])
    end

    it 'keeps vessel and aircraft names, MMSI, registration and tonnage variants' do
      expect(field(entities::Entity, :names)).to eq([vo::NameVariant, true])
      expect(field(entities::VesselEntity, :name)).to eq([string, false])
      expect(field(entities::VesselEntity, :mmsi_number)).to eq([string, false])
      expect(field(entities::VesselEntity, :tonnage)).to eq([vo::Tonnage, false])
      expect(field(entities::VesselEntity, :length)).to eq([Lutaml::Model::Type::Float, false])
      expect(field(entities::AircraftEntity, :registration)).to eq([string, false])
      expect(field(entities::AircraftEntity, :previous_registrations)).to eq([string, true])
    end

    it 'keeps the full SanctionEntry structure' do
      entry = sanction::SanctionEntry
      expect(field(entry, :list_type_detail)).to eq([sanction::ListType, false])
      expect(field(entry, :reason_details)).to eq([sanction::SanctionReason, true])
      expect(field(entry, :announcement_detail)).to eq([sanction::OfficialAnnouncement, false])
      expect(field(entry, :raw_source_detail)).to eq([vo::RawSourceData, false])
      expect(field(entry, :status_history)).to eq([sanction::StatusHistory, true])
      expect(field(entry, :legal_citations)).to eq([vo::LegalCitation, true])
      expect(field(entry, :modifications)).to eq([sanction::SanctionPeriodModification, true])
      expect(field(entry, :group_id)).to eq([string, false])
      expect(field(sanction::StatusHistory, :notice_reference)).to eq([vo::NoticeReference, false])
      expect(field(sanction::StatusHistory, :timestamp)).to eq([string, false])
    end
  end

  describe 'enumerations' do
    it 'narrows none of the accepted spellings on either side' do
      expect(Ammitto::Identification::TYPES).to include('Passport', 'NationalID', 'TaxID', 'DriversLicense',
                                                        'SocialSecurity', 'SeafarerID', 'MilitaryID',
                                                        'DiplomaticPassport', 'RefugeeID', 'Other')
      expect(Ammitto::SanctionEffect::SCOPES).to include('full', 'partial', 'limited')
      expect(Ammitto::LegalInstrument::TYPES).to include('act', 'ordinance', 'notice')
      expect(Ammitto::SanctionEntry::STATUSES).to include('resumed', 'terminated', 'deceased')
      expect(Ammitto::Ontology::Types::EFFECT_SCOPES).to include(:targeted, :sectoral)
      expect(Ammitto::Ontology::Types::SANCTION_STATUSES).to include(:pending)
    end
  end
end
