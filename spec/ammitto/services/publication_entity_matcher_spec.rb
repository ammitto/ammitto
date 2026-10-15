# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/services/publication_entity_matcher'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Services::PublicationEntityMatcher do
  subject(:matcher) { described_class.new }

  def row(source, suffix: 'one', type: 'PersonEntity', name: 'Alexander Petrov', dob: '1970-05-12', ids: [])
    node = { '@id' => "https://www.ammitto.org/entity/#{source}/#{suffix}",
             '@type' => type, 'names' => [{ 'fullName' => name }],
             'birthInfo' => dob ? [{ 'date' => dob }] : [], 'identifications' => ids }
    { source: source, node: node }
  end

  def passport(number = 'AB123456', country = 'GB')
    { 'type' => 'passport', 'number' => number, 'countryIsoCode' => country }
  end

  it 'links matching full birth dates plus conservatively fuzzy names symmetrically, retaining original data' do
    records = [row('un'), row('eu', name: 'Alexandr Petrov')]
    records.each { |record| record[:node]['hasSanctionEntry'] = ["entry-#{record[:source]}"] }
    before = Marshal.load(Marshal.dump(records))
    expect(matcher.resolve!(records).length).to eq(1)
    expect(matcher.matches.first[:evidence]).to eq('full_birth_date_and_name')
    expect(matcher.review_candidates).to be_empty
    records.each_with_index do |record, index|
      expect(record[:node]['sameAs']).to eq([records[1 - index][:node]['@id']])
      expect(record[:node].except('sameAs')).to eq(before[index][:node])
    end
  end

  it 'keeps fuzzy name-only matches as review candidates without publishing identity' do
    records = [row('un', dob: nil), row('eu', name: 'Alexandr Petrov', dob: nil)]
    expect(matcher.resolve!(records)).to be_empty
    expect(matcher.review_candidates.length).to eq(1)
    expect(records.map { |record| record[:node]['sameAs'] }).to eq([nil, nil])
  end

  it 'matches country-qualified typed identifiers even without names or dates' do
    records = [row('un', name: '', dob: nil, ids: [passport]), row('eu', name: '', dob: nil, ids: [passport('AB 123-456')])]
    expect(matcher.resolve!(records).first[:evidence]).to eq('qualified_identifier')
  end

  it 'does not match missing issuers, distinct issuers or distinct identifier types' do
    others = ['', 'ZZ', 'XX', 'AA', 'US'].map { |country| passport('AB123456', country) }
    others << passport.merge('type' => 'national_id')
    others.each do |other|
      expect(matcher.resolve!([row('un', dob: nil, ids: [passport]), row('eu', dob: nil, ids: [other])])).to be_empty
    end
  end

  it 'matches actual EU and US transformer passport spellings and ISO issuingCountry fields' do
    eu = { 'eu_reference_number' => 'EU.MATCH', 'logical_id' => 'MATCH',
           'subject_type' => { 'code' => 'person' },
           'name_aliases' => [{ 'whole_name' => 'EU Only Name' }],
           'identifications' => [{ 'identification_type_code' => 'passport', 'number' => 'AB123456', 'country_iso2_code' => 'GB' }] }
    us = { 'uid' => 'MATCH', 'sdn_type' => 'Individual', 'last_name' => 'Different Name',
           'id_list' => { 'items' => [{ 'id_type' => 'Passport', 'id_number' => 'AB123456', 'id_country' => 'GB' }] } }
    command = Ammitto::Cmd::HarmonizeCommand.new({}, %w[eu us])
    records = [[:eu, eu], [:us, us]].map do |source, input|
      { source: source, node: command.send(:transform_data, source, input)[:entity] }
    end
    expect(records.map { |record| record[:node]['identifications'].first }).to all(include('type' => 'Passport', 'issuingCountry' => 'GB'))
    expect(matcher.resolve!(records).first[:evidence]).to eq('qualified_identifier')
  end

  it 'does not use a contradictory countryIsoCode or an unknown display-country issuer' do
    others = [passport.merge('issuingCountry' => 'US'), passport.merge('countryIsoCode' => '', 'issuingCountry' => 'Unknown'),
              passport.merge('countryIsoCode' => 'ZZ', 'issuingCountry' => 'GB')]
    others.each do |other|
      expect(matcher.resolve!([row('un', dob: nil, ids: [passport]), row('eu', dob: nil, ids: [other])])).to be_empty
    end
  end

  it 'does not treat country-qualified company registration numbers as globally unique identities' do
    registration = { 'type' => 'CompanyRegistration', 'number' => 'AB123456', 'issuingCountry' => 'US' }
    records = [row('un', type: 'OrganizationEntity', dob: nil, ids: [registration]),
               row('eu', type: 'OrganizationEntity', dob: nil, ids: [registration])]
    expect(matcher.resolve!(records)).to be_empty
  end

  it 'rejects conflicting dates, identifiers and entity types despite other matching evidence' do
    [row('eu', dob: '1971-05-12', ids: [passport]),
     row('eu', ids: [passport('DIFFERENT')]),
     row('eu', type: 'OrganizationEntity', ids: [passport])].each do |other|
      expect(matcher.resolve!([row('un', ids: [passport]), other])).to be_empty
    end
  end

  it 'does not use partial, invalid, circa or range dates as birth-date identity evidence' do
    [{ 'date' => '1970' }, { 'date' => '1970-02-31' }, { 'date' => '1970-05-12', 'circa' => true },
     { 'date' => '1970-05-12', 'dateRangeTo' => '1970-06-12' }].each do |birth|
      other = row('eu')
      other[:node]['birthInfo'] = [birth]
      expect(matcher.resolve!([row('un'), other])).to be_empty
    end
  end

  it 'does not link intersecting but contradictory alternative birth dates' do
    other = row('eu')
    other[:node]['birthInfo'] << { 'date' => '1971-05-12' }
    expect(matcher.resolve!([row('un'), other])).to be_empty
  end

  it 'matches real canonical serialized date values and preserves range uncertainty' do
    serializer = Ammitto::Serialization::JsonLdSerializer.new
    records = %w[un eu].map do |source|
      person = Ammitto::PersonEntity.new(
        id: "https://www.ammitto.org/entity/#{source}/real", entity_type: 'person',
        names: [Ammitto::NameVariant.new(full_name: 'Alexander Petrov')],
        birth_info: [Ammitto::BirthInfo.new(date: Date.new(1970, 5, 12))]
      )
      { source: source, node: serializer.serialize_entity(person) }
    end
    expect(matcher.resolve!(records).length).to eq(1)
    uncertain = Ammitto::BirthInfo.new(date_range_from: Date.new(1970, 1, 1), date_range_to: Date.new(1971, 1, 1))
    records.last[:node]['birthInfo'] = [serializer.send(:serialize_birth_info, uncertain)]
    expect(matcher.resolve!(records)).to be_empty
  end

  it 'retains matching ambiguous birth alternatives as review leads without automatic identity' do
    records = [row('un'), row('eu')]
    records.each { |record| record[:node]['birthInfo'] << { 'date' => '1971-05-12' } }
    expect(matcher.resolve!(records)).to be_empty
    expect(matcher.review_candidates).to contain_exactly(
      ids: records.map { |record| record[:node]['@id'] }.sort, reason: 'name_similarity_requires_review'
    )
  end

  it 'does not infer identity from short common names and birth dates' do
    expect(matcher.resolve!([row('un', name: 'Li Li'), row('eu', name: 'Li Li')])).to be_empty
  end

  it 'matches checksum-valid vessel IMO numbers but rejects malformed checksums' do
    records = [row('un', type: 'VesselEntity', dob: nil), row('eu', type: 'VesselEntity', dob: nil)]
    records.each { |record| record[:node]['imoNumber'] = '9074729' }
    expect(matcher.resolve!(records).length).to eq(1)
    records = [row('un', type: 'VesselEntity', dob: nil), row('eu', type: 'VesselEntity', dob: nil)]
    records.each { |record| record[:node]['imoNumber'] = '9074720' }
    expect(matcher.resolve!(records)).to be_empty
  end

  it 'rejects an ambiguous component containing multiple entities from one source' do
    records = [row('un'), row('eu'), row('eu', suffix: 'two')]
    expect(matcher.resolve!(records)).to be_empty
    expect(matcher.review_candidates.length).to eq(2)
  end

  it 'rejects transitive bridges when every pair lacks sufficient compatible evidence' do
    records = [row('un', dob: nil, ids: [passport]), row('eu', ids: [passport]), row('uk')]
    expect(matcher.resolve!(records)).to be_empty
  end

  it 'links complete unambiguous multi-source components deterministically and preserves supplied links' do
    records = [row('un'), row('eu'), row('uk')]
    records.first[:node]['sameAs'] = ['https://example.org/original']
    expect(matcher.resolve!(records.reverse).length).to eq(3)
    expect(records.first[:node]['sameAs']).to include('https://example.org/original')
    first = Marshal.load(Marshal.dump(records))
    matcher.resolve!(records)
    expect(records).to eq(first)
  end

  it 'bounds fuzzy review work without consuming or changing strong automatic matches' do
    stub_const('Ammitto::Services::PublicationEntityMatcher::MAX_REVIEW_COMPARISONS', 1)
    weak = [row('a', dob: nil), row('b', dob: nil)]
    strong = [row('zz-a', name: '', dob: nil, ids: [passport]), row('zz-b', name: '', dob: nil, ids: [passport])]
    records = weak + strong
    expect(matcher.resolve!(records).length).to eq(1)
    expect(matcher.review_comparisons).to eq(1)
    expect(matcher.review_truncated).to be(true)
    matches = matcher.matches.dup
    expect(matcher.resolve!(records.reverse)).to eq(matches)
    expect(matcher.review_comparisons).to eq(1)
  end

  it 'bounds oversized blocks rather than comparing an unbounded popular name' do
    records = 60.times.map { |index| row("source#{index}", dob: nil) }
    expect(matcher.resolve!(records)).to be_empty
    expect(matcher.review_candidates).to be_empty
    expect(matcher.skipped_blocks).to be_positive
  end
end
