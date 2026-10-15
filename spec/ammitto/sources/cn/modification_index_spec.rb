# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/cn/modification_index'
require 'json'

RSpec.describe Ammitto::Sources::Cn::ModificationIndex do
  let(:updates) { File.expand_path('../../../fixtures/canonical_pipeline/cn/sources/sanction-updates', __dir__) }
  let(:index) { described_class.build(updates, Ammitto::Sources::Cn::Transformer.new) }
  let(:announcement) do
    Ammitto::OfficialAnnouncement.new(document_id: '〔2025〕7号', publish_date: Date.new(2025, 4, 4))
  end

  before { index.attach([entry], 'unreliable-entity-list', announcement) }

  shared_examples 'serializable attached history' do |entry_class, history_class, history_key, date_key|
    let(:entry) { entry_class.new(id: 'urn:test:entry', reference_number: 'ref') }

    it 'keeps the recipient history type and serializes its date natively' do
      expect(entry.status_history.first).to be_a(history_class)
      native = JSON.parse(entry.to_json)
      expect(native.fetch(history_key).first.fetch(date_key)).to eq('2025-05-14')
    end

    it 'publishes the modification date and notice in JSON-LD' do
      output = Ammitto::Serialization::JsonLdSerializer.new.serialize_entry(entry)
      history = JSON.parse(JSON.generate(output)).fetch('statusHistory').first
      expect(history.fetch('date')).to eq('2025-05-14')
      expect(history.fetch('noticeReference').fetch('noticeDate')).to eq('2025-05-14')
    end
  end

  context 'with a legacy entry' do
    it_behaves_like 'serializable attached history', Ammitto::SanctionEntry, Ammitto::StatusChange,
                    'statusHistory', 'date'
  end

  context 'with a canonical entry' do
    it_behaves_like 'serializable attached history', Ammitto::Ontology::Sanction::SanctionEntry,
                    Ammitto::Ontology::Sanction::StatusHistory, 'status_history', 'timestamp'
  end
end
