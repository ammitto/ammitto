# frozen_string_literal: true

require 'spec_helper'

# JsonLdSerializer reads a canonical model under the flat facade's field
# names without building the flat facade, whose types are narrower in
# places. A fractional vessel length is valid canonical data and publishes
# exactly; an integral one publishes as the integer the flat path always
# published.
RSpec.describe Ammitto::Serialization::JsonLdSerializer do
  let(:serializer) { described_class.new }
  let(:id) { 'https://www.ammitto.org/entity/au/edge' }

  def canonical_vessel(length)
    Ammitto::Ontology::Entities::VesselEntity.new(id: id, length: length)
  end

  it 'publishes a fractional canonical vessel length exactly' do
    node = serializer.serialize_entity(canonical_vessel(100.5))

    expect(node.values_at('@type', 'entityType', 'length')).to eq(['VesselEntity', 'vessel', 100.5])
    expect(JSON.parse(JSON.generate(node))['length']).to eq(100.5)
  end

  it 'publishes an integral canonical vessel length as an integer' do
    node = serializer.serialize_entity(canonical_vessel(100))

    expect(node['length']).to be(100)
    expect(JSON.generate(node)).to include('"length":100,')
  end

  it 'publishes a flat vessel and its canonical equivalent identically' do
    flat = Ammitto::VesselEntity.new(
      id: id, length: 120, imo_number: '9999999', flag_state: 'Panama',
      names: [Ammitto::NameVariant.new(full_name: 'EDGE CASE', script: 'Latn', is_primary: true)],
      tonnage: Ammitto::Tonnage.new(gross_tonnage: 3000),
      owner: Ammitto::EntityLink.new(target_id: 'https://www.ammitto.org/entity/au/owner', relationship: 'owner')
    )
    canonical = Ammitto::Ontology::Compatibility.canonical(flat)

    expect(canonical).to be_a(Ammitto::Ontology::Entities::VesselEntity)
    expect(serializer.serialize_entity(canonical)).to eq(serializer.serialize_entity(flat))
  end

  it 'uses the nearest registered canonical ancestor for every entity subclass type' do
    %w[Entity PersonEntity OrganizationEntity VesselEntity AircraftEntity].each do |name|
      parent = Ammitto::Ontology::Entities.const_get(name)
      value = Class.new(Class.new(parent)).new(id: id)
      expect(serializer.serialize_entity(value)['@type']).to eq(name)
      expect(Ammitto::Serialization::WireView.wrap(value)).to be_a(Ammitto::Serialization::WireView)
    end
  end

  it 'preserves vessel-specific fields and exact length on canonical subclasses' do
    klass = Class.new(Ammitto::Ontology::Entities::VesselEntity)
    value = klass.new(id: id, imo_number: '9999999', length: 100.5)
    node = serializer.serialize_entity(value)
    expect(node.values_at('@type', 'entityType', 'imoNumber', 'length'))
      .to eq(['VesselEntity', 'vessel', '9999999', 100.5])
    expect(JSON.parse(JSON.generate(node))['length']).to eq(100.5)
    flat = Class.new(Ammitto::VesselEntity).new(id: id, imo_number: '9999999', length: 100)
    expect(serializer.serialize_entity(flat).values_at('@type', 'imoNumber', 'length'))
      .to eq(['VesselEntity', '9999999', 100])
  end

  # The wire does not loosen the flat facade: projecting the same value
  # onto it is still refused rather than rounded
  it 'leaves the flat projection of a fractional length refused' do
    expect { Ammitto::Ontology::Compatibility.legacy(canonical_vessel(100.5)) }
      .to raise_error(Ammitto::Ontology::Compatibility::ConflictError)
  end
end
