# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/data/japan/meti/entity'
require 'ammitto/data/japan/meti/transformer'

RSpec.describe Ammitto::Data::Japan::METI::Transformer do
  let(:transformer) { described_class.new }

  let(:source_entity) do
    Ammitto::Data::Japan::METI::Entity.new(
      id: 'jp.meti.ful.1',
      name_en: "Al Qa'ida/Islamic Army",
      country_code: 'AF',
      country_ja: 'アフガニスタン',
      country_en: 'Islamic Republic of Afghanistan',
      wmd_types: %w[B C M N],
      aliases: ['Al Qaeda', 'The Base'],
      entity_type: 'organization',
      source_file: '20250929_4.xlsx',
      source_url: 'https://www.meti.go.jp/policy/anpo/20250929_4.xlsx',
      list_date: '2025-09-29',
      row_number: 1
    )
  end

  describe '#transform' do
    let(:result) { transformer.transform(source_entity) }

    it 'returns hash with entity and entry' do
      expect(result).to be_a(Hash)
      expect(result[:entity]).to be_a(Ammitto::OrganizationEntity)
      expect(result[:entry]).to be_a(Ammitto::SanctionEntry)
    end
  end

  describe '#create_organization_entity' do
    let(:entity) { transformer.send(:create_organization_entity, source_entity) }

    it 'creates OrganizationEntity with correct ID' do
      expect(entity.id).to eq('https://www.ammitto.org/entity/jp_meti/1')
    end

    it 'sets entity type to organization' do
      expect(entity.entity_type).to eq('organization')
    end

    it 'builds names with English as primary' do
      expect(entity.names).to be_an(Array)
      expect(entity.names.first.full_name).to eq("Al Qa'ida/Islamic Army")
      expect(entity.names.first.is_primary).to be true
    end

    it 'includes Japanese name' do
      ja_name = entity.names.find { |n| n.script == 'Jpan' }
      expect(ja_name).to be_nil # Source entity doesn't have Japanese name
    end

    it 'includes aliases' do
      alias_names = entity.names.reject(&:is_primary)
      expect(alias_names.count).to eq(2)
    end
  end

  describe '#build_names' do
    let(:names) { transformer.send(:build_names, source_entity) }

    it 'creates name variant for English name' do
      en_name = names.find { |n| n.script == 'Latn' && n.is_primary }
      expect(en_name).not_to be_nil
      expect(en_name.full_name).to eq("Al Qa'ida/Islamic Army")
    end

    it 'creates name variants for aliases' do
      alias_names = names.reject(&:is_primary)
      expect(alias_names.map(&:full_name)).to contain_exactly('Al Qaeda', 'The Base')
    end
  end

  describe '#build_source_references' do
    let(:refs) { transformer.send(:build_source_references, source_entity) }

    it 'creates source reference with correct code' do
      expect(refs.first.source_code).to eq('jp_meti')
    end

    it 'includes reference number' do
      expect(refs.first.reference_number).to eq('1')
    end

    it 'includes source URL when available' do
      expect(refs.first.url).to eq('https://www.meti.go.jp/policy/anpo/20250929_4.xlsx')
    end
  end

  describe '#create_entry' do
    let(:entity) { transformer.send(:create_organization_entity, source_entity) }
    let(:entry) { transformer.send(:create_entry, source_entity, entity) }

    it 'creates SanctionEntry with correct ID' do
      expect(entry.id).to eq('https://www.ammitto.org/entry/jp_meti/foreign-user-list/1')
    end

    it 'links to the entity' do
      expect(entry.entity_id).to eq(entity.id)
    end

    it 'sets authority to jp_meti' do
      expect(entry.authority).to be_a(Ammitto::Authority)
      expect(entry.authority.id).to eq('jp_meti')
    end

    it 'sets status to active' do
      expect(entry.status).to eq('active')
    end

    it 'includes export restriction effect' do
      expect(entry.effects).to be_an(Array)
      effect_types = entry.effects.map(&:effect_type)
      expect(effect_types).to include('export_restriction')
    end

    it 'includes WMD proliferation reasons' do
      expect(entry.reasons).to be_an(Array)
      expect(entry.reasons.count).to eq(4) # B, C, M, N
    end
  end

  describe '#create_regime' do
    let(:regime) { transformer.send(:create_regime) }

    it 'creates regime with correct name' do
      expect(regime.name).to eq('Japan METI Foreign User List')
    end

    it 'creates regime with correct code' do
      expect(regime.code).to eq('JP-METI-FUL')
    end
  end

  describe '#build_effects' do
    let(:effects) { transformer.send(:build_effects) }

    it 'includes export restriction effect' do
      expect(effects).to be_an(Array)
      export_effect = effects.find { |e| e.effect_type == 'export_restriction' }
      expect(export_effect).not_to be_nil
      expect(export_effect.description).to include('export license')
    end
  end

  describe '#build_reasons' do
    let(:reasons) { transformer.send(:build_reasons, source_entity) }

    it 'creates reasons for each WMD type' do
      expect(reasons.count).to eq(4)
    end

    it 'includes correct category' do
      reasons.each do |reason|
        expect(reason.category).to eq('wmd_proliferation')
      end
    end

    it 'includes descriptions for WMD types' do
      # description is an array of LocalizedString objects
      description_texts = reasons.flat_map do |reason|
        reason.description.map(&:value)
      end
      expect(description_texts).to include(match(/biological weapons/i))
      expect(description_texts).to include(match(/chemical weapons/i))
      expect(description_texts).to include(match(/missiles/i))
      expect(description_texts).to include(match(/nuclear weapons/i))
    end
  end

  describe '#create_period' do
    let(:period) { transformer.send(:create_period, source_entity) }

    it 'sets indefinite to true' do
      expect(period.is_indefinite).to be true
    end

    it 'includes list date when available' do
      expect(period.listed_date).to eq(Date.new(2025, 9, 29))
    end
  end
end
