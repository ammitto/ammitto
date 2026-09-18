# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/cn/announcement'

RSpec.describe Ammitto::Sources::Cn::Entity do
  describe '#list_type_code' do
    def code_for(value)
      described_class.new(sanction_list: value).list_type_code
    end

    it 'matches the Chinese labels from the schema enum' do
      expect(code_for('反制裁清单')).to eq('anti_sanctions')
      expect(code_for('不可靠实体清单')).to eq('unreliable_entity')
      expect(code_for('出口管制管控名单')).to eq('export_control')
    end

    it 'matches the source-prefixed slugs the data stores' do
      expect(code_for('cn/anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('cn/unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('cn/import-export-control-list')).to eq('export_control')
    end

    it 'matches bare slugs without the source prefix' do
      expect(code_for('anti-sanction-list')).to eq('anti_sanctions')
      expect(code_for('unreliable-entity-list')).to eq('unreliable_entity')
      expect(code_for('import-export-control-list')).to eq('export_control')
    end

    it 'ignores surrounding whitespace' do
      expect(code_for(" cn/anti-sanction-list\n")).to eq('anti_sanctions')
    end

    it 'returns unknown for unrecognized, empty, and nil values' do
      expect(code_for('no-such-list')).to eq('unknown')
      expect(code_for('')).to eq('unknown')
      expect(code_for(nil)).to eq('unknown')
    end
  end

  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'prefers english_name when it is present' do
      entity = described_class.new(name: { 'en' => 'Acme Corp', 'zh-Hans' => '爱堪公司' })

      expect(entity.identifier).to eq('Acme Corp')
    end

    it 'falls through to chinese_name when english_name is blank' do
      entity = described_class.new(name: { 'en' => '', 'zh-Hans' => '爱堪公司' })

      expect(entity.identifier).to eq('爱堪公司')
    end

    it 'is nil when the record carries no name at all' do
      entity = described_class.new(name: nil)

      expect(entity.identifier).to be_nil
    end
  end
end
