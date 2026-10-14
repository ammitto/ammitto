# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

# A source describes an effect either with one text or with one
# LocalizedString per language, and each has its own typed field. A text in
# the LocalizedString collection still reached the JSON-LD, which copies
# the value through, but native serialization of the same model refused it
# (Lutaml::Model::IncorrectModelError). These run the production harmonize
# path over the actual records whose effects carry descriptions.
RSpec.describe 'Sanction effect descriptions' do
  fixtures = CanonicalPipelineFixtures

  before do
    allow(Time).to receive(:now).and_return(fixtures::PINNED_TIME)
    allow(Date).to receive(:today).and_return(fixtures::PINNED_TIME.to_date)
  end

  native_effects = ->(model) { JSON.parse(model.to_json).fetch('effects', []) }

  # Each branch whose published effects carry a description, with the
  # published description of every effect in order (nil where none)
  described = fixtures.branches.filter_map do |branch|
    output = JSON.parse(File.read(fixtures.golden_path(branch))).dig('json', 'output')
    entries = (output.is_a?(Array) ? output : [output]).filter_map { |pair| pair['entry'] }
    published = entries.flat_map { |entry| entry['effects'] }.map { |effect| effect['description'] }
    [branch, published] if published.any?
  end

  it 'covers effects described by text and by LocalizedStrings' do
    kinds = described.flat_map { |_, published| published.compact.map(&:class) }.uniq
    expect(kinds).to contain_exactly(String, Array)
  end

  described.each do |branch, published|
    context "with #{fixtures.label(branch)}" do
      let(:entries) { fixtures.run(branch)[:models].grep(Ammitto::Ontology::Sanction::SanctionEntry) }
      let(:effects) { entries.flat_map(&:effects) }
      let(:canonical_json) { entries.flat_map { |entry| native_effects.call(entry) } }
      let(:legacy_json) do
        entries.flat_map { |entry| native_effects.call(Ammitto::Ontology::Compatibility.legacy(entry)) }
      end

      if published.compact.first.is_a?(String)
        it 'keeps the text in the scalar description, not the LocalizedString collection' do
          expect(effects.map(&:description)).to eq(published)
          expect(effects.map { |effect| Array(effect.localized_descriptions) }.uniq).to eq([[]])
        end

        it 'serializes natively as description, and descriptionText on the flat projection' do
          expect(canonical_json.map { |effect| effect['description'] }).to eq(published)
          expect(legacy_json.map { |effect| effect['descriptionText'] }).to eq(published)
          expect(legacy_json.map { |effect| effect.key?('description') }.uniq).to eq([false])
        end
      else
        it 'keeps the LocalizedStrings in their collection and no scalar description' do
          expect(effects.map(&:description).compact).to eq([])
          expect(effects.map { |effect| effect.localized_descriptions.map(&:class).uniq })
            .to all(eq([Ammitto::Ontology::ValueObjects::LocalizedString]))
        end

        it 'serializes natively with every LocalizedString' do
          expect(canonical_json.map { |effect| effect['localized_descriptions'] }).to eq(published)
          expect(legacy_json.map { |effect| effect['description'] }).to eq(published)
        end
      end
    end
  end
end
