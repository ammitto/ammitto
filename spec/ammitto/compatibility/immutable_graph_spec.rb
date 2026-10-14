# frozen_string_literal: true

require 'spec_helper'
require 'date'
require_relative '../../support/compatibility_sentinels'

RSpec.describe 'Canonical graph ownership' do
  let(:conversion) { Ammitto::Ontology::Compatibility }
  let(:vo) { Ammitto::Ontology::ValueObjects }

  %w[NameVariant Address Identification BirthInfo LegalInstrument SanctionEffect TemporalPeriod ContactInfo
     EntityLink SourceReference Tonnage LocalizedString LegalCitation NoticeReference RawSourceData].each do |name|
    it "seals #{name} across construction, factories, replacements and copies" do
      klass = Ammitto::Ontology::ValueObjects.const_get(name)
      value = CompatibilitySentinels.build(klass)
      expect(value).to be_frozen
      [klass.from_json(value.to_json), klass.from_yaml(value.to_yaml), value.with,
       value.dup, value.clone(freeze: false), Marshal.load(Marshal.dump(value))].each do |copy|
        expect(copy).to be_frozen
        expect(copy.class).to eq(klass)
      end
    end
  end

  %w[ListType OfficialAnnouncement SanctionReason StatusHistory SanctionPeriodModification].each do |name|
    it "seals the #{name} value container and nested fields" do
      klass = Ammitto::Ontology::Sanction.const_get(name)
      value = CompatibilitySentinels.build(klass)
      expect(value).to be_frozen
      expect([klass.from_json(value.to_json), klass.from_yaml(value.to_yaml), value.with,
              Marshal.load(Marshal.dump(value))]).to all(be_frozen)
      klass.attributes.each_key do |key|
        field = value.public_send(key)
        expect(field).to be_frozen if field.is_a?(Array) || field.is_a?(String) || field.is_a?(Date)
      end
    end
  end

  it 'owns Date and Time attached state in both conversion directions without freezing legacy data' do
    date = Date.new(2026, 1, 2)
    date.instance_variable_set(:@notes, ['source'.dup])
    flat = Ammitto::TemporalPeriod.new(listed_date: date)
    canonical = conversion.canonical(flat)
    legacy = conversion.legacy(canonical)
    expect(canonical.listed_date).not_to equal(flat.listed_date)
    expect(legacy.listed_date).not_to equal(canonical.listed_date)
    expect(legacy.listed_date).not_to be_frozen
    legacy.listed_date.instance_variable_get(:@notes).first << ' legacy changed'
    expect(canonical.listed_date.instance_variable_get(:@notes)).to eq(['source'])
    expect(flat.listed_date.instance_variable_get(:@notes)).to eq(['source'])

    time = Time.new(2026, 1, 2, 3, 4, 5, '+05:00')
    time.instance_variable_set(:@metadata, { 'tags' => ['source'.dup] })
    raw = Ammitto::RawSourceData.new(source_specific_fields: { 'at' => time })
    owned = conversion.canonical(raw)
    back = conversion.legacy(owned)
    back.source_specific_fields['at'].gmtime
    back.source_specific_fields['at'].instance_variable_get(:@metadata)['tags'].first << ' changed'
    expect(raw.source_specific_fields['at'].utc_offset).to eq(18_000)
    expect(owned.source_specific_fields['at'].utc_offset).to eq(18_000)
    expect(owned.source_specific_fields['at'].instance_variable_get(:@metadata)['tags']).to eq(['source'])
  end

  it 'copies Hash keys, defaults, identity comparison and attached state without caller aliases' do
    keys = ['equal'.dup, 'equal'.dup]
    hash = {}.compare_by_identity
    hash.default = ['default'.dup]
    keys.each_with_index { |key, index| hash[key] = index }
    hash.instance_variable_set(:@notes, ['source'.dup])
    %i[canonical legacy].each do |side|
      copy = conversion.public_send(side, hash)
      expect(copy).to be_compare_by_identity
      expect(copy.size).to eq(2)
      expect(copy.default).to eq(['default'])
      expect(copy.default).not_to equal(hash.default)
      expect(copy.keys.first).not_to equal(keys.first)
      copy.keys.first << ' changed'
      copy.default.first << ' changed'
      copy.instance_variable_get(:@notes).first << ' changed'
      expect(keys).to eq(%w[equal equal])
      expect(hash.default).to eq(['default'])
      expect(hash.instance_variable_get(:@notes)).to eq(['source'])
    end
  end

  it 'copies String attached state and rejects cycles or mutable Hash default procs clearly' do
    text = 'source'.dup
    text.instance_variable_set(:@notes, ['source'.dup])
    copy = conversion.legacy(text)
    copy.instance_variable_get(:@notes).first << ' changed'
    expect(text.instance_variable_get(:@notes)).to eq(['source'])
    cyclic = []
    cyclic.instance_variable_set(:@cycle, cyclic)
    expect { conversion.canonical(cyclic) }.to raise_error(Ammitto::Ontology::Compatibility::ConflictError, /Cyclic/)
    expect(cyclic).not_to be_frozen
    expect { conversion.legacy(Hash.new { [] }) }.to raise_error(Ammitto::Ontology::Compatibility::ConflictError, /default proc/)
  end

  it 'retains owned String attachments through native legacy setters and ordinary Hash keys' do
    text = 'source'.dup
    text.instance_variable_set(:@notes, ['source'.dup])
    canonical = vo::NameVariant.new(full_name: text)
    legacy = conversion.legacy(canonical)
    expect(legacy.full_name.instance_variable_get(:@notes)).to eq(['source'])
    legacy.full_name.instance_variable_get(:@notes).first << ' changed'
    expect(canonical.full_name.instance_variable_get(:@notes)).to eq(['source'])
    key = 'key'.dup
    key.instance_variable_set(:@notes, ['source'.dup])
    key.freeze
    source = { key => 'value' }
    copy = conversion.legacy(source)
    expect(copy.keys.first.instance_variable_get(:@notes)).to eq(['source'])
    copy.keys.first.instance_variable_get(:@notes).first << ' changed'
    expect(key.instance_variable_get(:@notes)).to eq(['source'])
    raw = vo::RawSourceData.new(source_specific_fields: source)
    expect(raw.source_specific_fields.keys.first.instance_variable_get(:@notes)).to eq(['source'])
    expect(raw.source_specific_fields.keys.first.instance_variable_get(:@notes).first).to be_frozen
  end

  it 'preserves collection attachments through construction, builders, replacement and mapping factories' do
    values = ['first'.dup]
    values.instance_variable_set(:@metadata, { 'notes' => ['source'.dup] })
    klass = Ammitto::Ontology::Sanction::ListType
    copies = [klass.new(localized_name: values), klass.new { |value| value.localized_name = values },
              klass.new.with(localized_name: values), klass.of_json('localized_name' => values),
              klass.apply_mappings({ 'localized_name' => values }, :json)]
    copies.each do |value|
      metadata = value.localized_name.instance_variable_get(:@metadata)
      expect(metadata).to eq('notes' => ['source'])
      expect(metadata).to be_frozen
      expect(metadata['notes'].first).to be_frozen
      expect(value.localized_name).to be_frozen
    end
    values.instance_variable_get(:@metadata)['notes'].first << ' changed'
    copies.each do |value|
      expect(value.localized_name.instance_variable_get(:@metadata)).to eq('notes' => ['source'])
    end
    expect(values).not_to be_frozen
  end

  it 'preserves array state through canonical and legacy mutable entity collection setters' do
    source = Ammitto::PersonEntity.new(nationalities: ['AA'])
    source.nationalities.instance_variable_set(:@metadata, ['source'.dup])
    canonical = conversion.canonical(source)
    legacy = conversion.legacy(canonical)
    expect(canonical.nationalities.instance_variable_get(:@metadata)).to eq(['source'])
    expect(legacy.nationalities.instance_variable_get(:@metadata)).to eq(['source'])
    legacy.nationalities.instance_variable_get(:@metadata).first << ' changed'
    expect(canonical.nationalities.instance_variable_get(:@metadata)).to eq(['source'])
    expect(source.nationalities.instance_variable_get(:@metadata)).to eq(['source'])
  end

  it 'does not collapse identity Hash entries or compare different defaults and attached state as equal' do
    source = {}.compare_by_identity
    source['same'.dup] = 1
    source['same'.dup] = 2
    expect(conversion.equivalent?(source, 'same' => 2)).to be false
    expect(conversion.equivalent?(source, conversion.canonical(source))).to be true
    left = { 'a' => 1 }
    right = { 'a' => 1 }
    left.default = ['left']
    right.default = ['right']
    expect(conversion.equivalent?(left, right)).to be false
    right.default = ['left']
    left.instance_variable_set(:@metadata, ['left'])
    right.instance_variable_set(:@metadata, ['right'])
    expect(conversion.equivalent?(left, right)).to be false
    expect(conversion.equivalent?({ 1 => 'value' }, 1.0 => 'value')).to be false
    expect(conversion.equivalent?({ 'a' => 1, 'b' => 2 }, 'b' => 2, 'a' => 1)).to be true
    infinite = { 'a' => Float::INFINITY, 'b' => -Float::INFINITY }
    expect(conversion.equivalent?(infinite, conversion.legacy(infinite))).to be true
  end

  it 'normalizes model Hash keys without losing identity entries, defaults or metadata' do
    keys = 2.times.map { Ammitto::NameVariant.new(full_name: 'Key name') }
    fields = {}.compare_by_identity
    keys.each_with_index { |key, index| fields[key] = index }
    fields.default = ['fallback'.dup]
    fields.instance_variable_set(:@metadata, { 'note' => 'source'.dup })
    source = Ammitto::RawSourceData.new(source_specific_fields: fields)
    source.source_specific_fields.default = ['fallback'.dup]
    source.source_specific_fields.instance_variable_set(:@metadata, { 'note' => 'source'.dup })
    canonical = conversion.canonical(source)
    back = conversion.legacy(canonical)
    expect(canonical.source_specific_fields.size).to eq(2)
    expect(canonical.source_specific_fields.keys).to all(be_a(vo::NameVariant))
    expect(back.source_specific_fields.keys).to all(be_a(Ammitto::NameVariant))
    expect(conversion.equivalent?(source, canonical)).to be true
    expect(conversion.snapshot(back)).to eq(conversion.snapshot(source))
    ordinary = Ammitto::RawSourceData.new(source_specific_fields: { keys.first => 'data' })
    expect(conversion.canonical(ordinary).source_specific_fields.keys.first).to be_a(vo::NameVariant)
    back.source_specific_fields.default.first << ' changed'
    back.source_specific_fields.instance_variable_get(:@metadata)['note'] << ' changed'
    expect(canonical.source_specific_fields.default).to eq(['fallback'])
    expect(canonical.source_specific_fields.instance_variable_get(:@metadata)).to eq('note' => 'source')
  end

  it 'compares fractional temporal values losslessly with and without attached state' do
    times = [Time.at(123, 100, :nanosecond), Time.at(123, 200, :nanosecond)]
    dates = [DateTime.new(2026, 1, 1, 0, 0, Rational(1, 10)),
             DateTime.new(2026, 1, 1, 0, 0, Rational(2, 10))]
    [times, dates].each do |values|
      expect(conversion.equivalent?(*values)).to be false
      values.each { |value| value.instance_variable_set(:@metadata, ['same']) }
      expect(conversion.equivalent?(*values)).to be false
      raw = values.map { |value| Ammitto::RawSourceData.new(source_specific_fields: { 'at' => value }) }
      expect(conversion.equivalent?(*raw)).to be false
      expect(conversion.equivalent?(raw.first, conversion.canonical(raw.first))).to be true
    end
  end

  it 'compares Hash entry multisets without lossy ordering or binary encoding' do
    keys = [Time.at(123, 100, :nanosecond), Time.at(123, 200, :nanosecond)]
    left = { keys[0] => 'same', keys[1] => 'same' }
    right = { keys[1] => 'same', keys[0] => 'same' }
    expect(left).to eq(right)
    expect(conversion.equivalent?(left, right)).to be true
    expect(conversion.equivalent?(left, keys.first => 'same')).to be false
    raw = Ammitto::RawSourceData.new(source_specific_fields: { 'bytes' => "\xFF".b })
    canonical = conversion.canonical(raw)
    expect(canonical.source_specific_fields['bytes'].bytes).to eq([255])
    expect(conversion.equivalent?(raw, canonical)).to be true
    expect(conversion.equivalent?({ "\xFF".b => 'value' }, conversion.legacy("\xFF".b) => 'value')).to be true
  end

  it 'keeps legacy String values mutable when the source also uses them as Hash keys' do
    key = 'same'.dup.freeze
    source = { key => key }
    legacy = conversion.legacy(source)
    expect(legacy.keys.first).to be_frozen
    expect(legacy.values.first).not_to be_frozen
    expect(legacy.values.first).not_to equal(key)
    legacy.values.first << ' changed'
    expect(key).to eq('same')
    expect(legacy.keys.first).to eq('same')
  end

  it 'preserves completed model references in an owned conversion without accepting cycles' do
    entry = Ammitto::Ontology::Sanction::SanctionEntry.new(id: 'https://example.org/entry', status: 'active')
    entity = Ammitto::Ontology::Entities::PersonEntity.new(id: 'https://example.org/entity')
    entity.add_sanction_entry(entry)
    source = { entity: entity, entry: entry }
    legacy = conversion.legacy(source)
    expect(legacy[:entity].sanction_entries.first).to equal(legacy[:entry])
    expect(legacy[:entry]).not_to equal(entry)
    legacy[:entry].status = 'changed'
    expect(legacy[:entity].sanction_entries.first.status).to eq('changed')
    expect(entry.status).to eq('active')
    canonical = conversion.canonical(legacy)
    expect(canonical[:entity].sanction_entries.first).to equal(canonical[:entry])
    expect(canonical[:entry]).not_to equal(legacy[:entry])
    cyclic = []
    cyclic << cyclic
    expect { conversion.legacy(cyclic) }.to raise_error(Ammitto::Ontology::Compatibility::ConflictError, /Cyclic/)
    other = conversion.legacy(source)
    expect(other[:entry]).not_to equal(legacy[:entry])
  end

  %w[PersonEntity OrganizationEntity].each do |name|
    it "preserves a note-only contact in #{name} hash output while leaving entity identity mutable" do
      source = Ammitto.const_get(name).new(contact_info: Ammitto::ContactInfo.new(note: 'only source note'))
      value = conversion.canonical(source)
      expect(value.contact_info).to be_present
      expect(value.to_hash).to include(contact_info: { note: 'only source note' })
      expect(value).not_to be_frozen
      value.id = 'https://example.org/changed'
      expect(value.contact_info).to be_frozen
    end
  end
end
