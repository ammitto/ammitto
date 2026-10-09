# frozen_string_literal: true

require 'digest'
require 'spec_helper'

RSpec.describe Ammitto::Utils::IriSanitizer do
  ca_schedules = {
    'Extremist-Settler-Violence-Violence-extr-miste-des-colons-Part-1-' => 19,
    'Extremist-Settler-Violence-Violence-extr-miste-des-colons-Part-2-' => 12,
    'Justice-for-Victims-of-Corrupt-Foreign-Officials-Regulations-JVCFOR-' \
    'R-glement-relatif-la-justice-pour-les-victimes-de-dirigeants-' \
    'trangers-corrompus-RJVDEC-' => 80
  }.freeze
  ca_ids = ca_schedules.flat_map do |prefix, count|
    (1..count).map { |number| "#{prefix}#{number}" }
  end.freeze
  tr_id = 'ESFAHAN NUCLEAR FUEL RESEARCH AND PRODUCTION CENTRE (NFRPC) ' \
          'AND ESFAHAN NUCLEAR TECHNOLOGY CENTRE(ENTC)'

  def mint_entity_ids(ids, order: ids)
    registry = described_class::CollisionRegistry.new
    order.each { |id| described_class.entity_iri('ca', id, collision_registry: registry) }
    registry.finalize!
    ids.to_h do |id|
      [id, described_class.entity_iri('ca', id, collision_registry: registry)]
    end
  end

  def mint_entry_ids(ids, list_type: 'consolidated-list')
    registry = described_class::CollisionRegistry.new
    ids.each do |id|
      described_class.entry_iri('ca', list_type, id, collision_registry: registry)
    end
    registry.finalize!
    ids.to_h do |id|
      [id, described_class.entry_iri('ca', list_type, id, collision_registry: registry)]
    end
  end

  it 'splits all real ca ids and is independent of record order' do
    ordered = mint_entity_ids(ca_ids)
    shuffled = mint_entity_ids(ca_ids.reverse)

    expect(ordered).to eq(shuffled)
    expect(ordered.values.map(&:itself).uniq.size).to eq(111)
  end

  it 'splits the corresponding ca entries in their list scope' do
    entries = mint_entry_ids(ca_ids)

    expect(entries.values.uniq.size).to eq(111)
  end

  it 'keeps the tr record on its existing plain-cut entity and entry IRIs' do
    registry = described_class::CollisionRegistry.new
    described_class.entity_iri('tr', tr_id, collision_registry: registry)
    described_class.entry_iri('tr', 'consolidated-list', tr_id,
                              collision_registry: registry)
    registry.finalize!

    expect(described_class.entity_iri('tr', tr_id,
                                      collision_registry: registry)).to eq(
                                        'https://www.ammitto.org/entity/tr/' \
                                        'esfahan-nuclear-fuel-research-and-production-centre-nfrpc-and-es'
                                      )
    expect(described_class.entry_iri('tr', 'consolidated-list', tr_id,
                                     collision_registry: registry)).to eq(
                                       'https://www.ammitto.org/entry/tr/consolidated-list/' \
                                       'esfahan-nuclear-fuel-research-and-production-centre-nfrpc-and-es'
                                     )
  end

  it 'digests only long ids in a collision bucket' do
    first = "#{'a' * 64}1"
    second = "#{'a' * 64}2"
    short = 'a' * 64
    registry = described_class::CollisionRegistry.new
    [first, second, short].each do |id|
      described_class.entity_iri('ca', id, collision_registry: registry)
    end
    registry.finalize!

    expected = lambda do |id|
      "#{'a' * 55}-#{Digest::SHA256.hexdigest(id)[0, 8]}"
    end
    expect(described_class.entity_iri('ca', first,
                                      collision_registry: registry)).to end_with(expected.call(first))
    expect(described_class.entity_iri('ca', second,
                                      collision_registry: registry)).to end_with(expected.call(second))
    expect(described_class.entity_iri('ca', short,
                                      collision_registry: registry)).to end_with(short)
  end

  it 'keeps a digest id from aliasing a plain id when the head ends in a hyphen' do
    prefix = "#{'a' * 54}-"
    first = "#{prefix}#{'b' * 9}x"
    second = "#{prefix}#{'b' * 9}y"
    registry = described_class::CollisionRegistry.new
    [first, second].each do |id|
      described_class.entity_iri('ca', id, collision_registry: registry)
    end
    registry.finalize!

    digest_id = described_class.entity_iri('ca', first,
                                           collision_registry: registry).split('/').last
    plain_id = "#{'a' * 54}-#{Digest::SHA256.hexdigest(first)[0, 8]}"

    expect(digest_id.length).to eq(64)
    expect(digest_id).not_to eq(plain_id)
  end

  it 'does not digest a lone long id' do
    lone = 'b' * 80
    registry = described_class::CollisionRegistry.new
    described_class.entity_iri('ca', lone, collision_registry: registry)
    registry.finalize!

    iri = described_class.entity_iri('ca', lone, collision_registry: registry)
    expect(iri).to end_with('b' * 64)
  end

  it 'does not digest an identical sanitized duplicate' do
    lone = 'b' * 80
    duplicate = " #{lone.upcase} "
    registry = described_class::CollisionRegistry.new
    [lone, duplicate].each do |id|
      described_class.entity_iri('ca', id, collision_registry: registry)
    end
    registry.finalize!

    iri = described_class.entity_iri('ca', lone, collision_registry: registry)
    expect(described_class.entity_iri('ca', duplicate,
                                      collision_registry: registry)).to eq(iri)
  end

  it 'does not treat different entry list types as one collision scope' do
    ids = ["#{'c' * 64}1", "#{'c' * 64}2"]
    registry = described_class::CollisionRegistry.new
    described_class.entry_iri('ca', 'list-a', ids.first,
                              collision_registry: registry)
    described_class.entry_iri('ca', 'list-b', ids.last,
                              collision_registry: registry)
    registry.finalize!

    ids.each_with_index do |id, index|
      list = "list-#{('a'.ord + index).chr}"
      expect(described_class.entry_iri('ca', list, id,
                                       collision_registry: registry)).to end_with('c' * 64)
    end
  end

  it 'canonicalizes entry list types before assigning collision scopes' do
    ids = ["#{'d' * 64}1", "#{'d' * 64}2"]
    registry = described_class::CollisionRegistry.new
    described_class.entry_iri('ca', 'list a', ids.first,
                              collision_registry: registry)
    described_class.entry_iri('ca', 'list-a', ids.last,
                              collision_registry: registry)
    registry.finalize!

    iris = ids.each_with_index.map do |id, index|
      list = index.zero? ? 'list a' : 'list-a'
      described_class.entry_iri('ca', list, id, collision_registry: registry)
    end

    expect(iris.map { |iri| iri.split('/').last }).to all(match(/-\h{8}\z/))
    expect(iris.uniq.size).to eq(2)
  end

  it 'keeps entity_iri_from_entry pointing at the emitted entity across list scopes' do
    ids = ["#{'e' * 64}1", "#{'e' * 64}2"]
    registry = described_class::CollisionRegistry.new
    ids.zip(%w[list-a list-b]).each do |id, list|
      described_class.entity_iri('ca', id, collision_registry: registry)
      described_class.entry_iri('ca', list, id, collision_registry: registry)
    end
    registry.finalize!

    ids.zip(%w[list-a list-b]).each do |id, list|
      entry = described_class.entry_iri('ca', list, id, collision_registry: registry)
      entity = described_class.entity_iri('ca', id, collision_registry: registry)
      expect(described_class.entity_iri_from_entry(entry)).to eq(entity)
    end
  end

  it 'refuses an entity-forced entry digest that aliases another plain entry id' do
    ids = ["#{'f' * 64}1", "#{'f' * 64}2"]
    alias_id = "#{'f' * 55}-#{Digest::SHA256.hexdigest(ids.first)[0, 8]}"
    registry = described_class::CollisionRegistry.new
    ids.each { |id| described_class.entity_iri('ca', id, collision_registry: registry) }
    described_class.entry_iri('ca', 'list-a', ids.first, collision_registry: registry)
    described_class.entry_iri('ca', 'list-a', alias_id, collision_registry: registry)

    expect { registry.finalize! }.to raise_error(Ammitto::ParseError, /collide after sanitization/)
  end
end
