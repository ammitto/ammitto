# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'
require 'ammitto/data/japan/meti/entity'
require 'ammitto/data/japan/meti/transformer'

# Issue 13 acceptance for the production harmonize path. Each record in
# spec/fixtures/canonical_pipeline goes through HarmonizeCommand's own
# #transform_data, and the examples inspect what that path handed the
# serializer as well as what it emitted: canonical ontology models, sealed
# value objects, and byte-for-byte the JSON-LD the flat pipeline emitted.
RSpec.describe 'Canonical transformer pipeline' do
  fixtures = CanonicalPipelineFixtures

  before do
    allow(Time).to receive(:now).and_return(fixtures::PINNED_TIME)
    allow(Date).to receive(:today).and_return(fixtures::PINNED_TIME.to_date)
  end

  # Every record shape #transform_data dispatches on, per registered source.
  # A source or branch added to the dispatch must add a record here and in
  # the manifest; one missing from the manifest fails the coverage example.
  branches_by_source = {
    uk: %w[individual entity ship],
    eu: %w[person enterprise],
    un: %w[individual entity],
    us: %w[individual entity vessel aircraft],
    wb: %w[person organization],
    au: %w[individual organization vessel generic],
    ca: %w[individual entity vessel],
    ch: %w[target_individual target_entity target_object identity],
    cn: %w[announcement modification],
    ru: %w[announcement per_entity],
    nz: %w[individual entity ship],
    tr: %w[person organization],
    eu_vessels: %w[vessel],
    jp: %w[announcement_top_level announcement_nested flat],
    un_vessels: %w[vessel]
  }

  # The value-object classes issue 13 requires to be immutable, plus the
  # nested values a canonical entry reaches through them.
  value_object = lambda do |model|
    name = model.class.name.to_s
    name.start_with?('Ammitto::Ontology::ValueObjects::') ||
      %w[Ammitto::Ontology::Sanction::ListType Ammitto::Ontology::Sanction::OfficialAnnouncement].include?(name)
  end

  # Frozen, and so are the strings it holds
  sealed = lambda do |model|
    model.frozen? && model.class.attributes.each_key.all? do |name|
      value = model.public_send(name)
      !value.is_a?(String) || value.frozen?
    end
  end

  it 'declares branches for exactly the registered sources' do
    expect(branches_by_source.keys).to match_array(Ammitto::Transformers::Registry.supported_sources)
  end

  it 'has a record and a golden document for every declared branch' do
    declared = branches_by_source.flat_map { |source, names| names.map { |name| "#{source}__#{name}" } }
    present = fixtures.branches.select do |branch|
      File.file?(fixtures.fixture_path(branch)) && File.file?(fixtures.golden_path(branch))
    end
    expect(declared - present.map { |branch| fixtures.label(branch) }).to eq([])
  end

  # A synthetic record stands in only where no published record reaches the
  # branch, and says so with the evidence; anything new needs an actual one
  it 'uses an actual record wherever one is published' do
    records = fixtures.branches + fixtures.extras
    provenance = records.to_h do |record|
      [fixtures.label(record), %w[origin derived synthetic].select { |key| record.key?(key) }]
    end
    synthetic = records.select { |record| record.key?('synthetic') }

    expect(provenance.values.map(&:size).uniq).to eq([1])
    expect(synthetic.map { |record| fixtures.label(record) }).to eq(%w[au__generic ru__per_entity jp_meti__entity])
    expect(synthetic.map { |record| record['absence_proof'].to_s.empty? }.uniq).to eq([false])
  end

  # No source reaches the serializer through a converting fallback
  it 'gives every registered transformer canonical entrypoints' do
    flat = Ammitto::Transformers::Registry.supported_sources.reject do |source|
      Ammitto::Transformers::Registry.get(source).class.canonical?
    end
    expect(flat).to eq([])
  end

  fixtures.branches.each do |branch|
    context "with #{branch['source']} #{branch['branch']}" do
      let(:result) { fixtures.run(branch) }
      let(:golden) { JSON.parse(File.read(fixtures.golden_path(branch))) }
      let(:pairs) do
        output = golden.dig('json', 'output')
        output.is_a?(Array) ? output : [output]
      end
      let(:reachable) { fixtures.reachable_models(result[:models]) }

      it 'emits the JSON-LD the flat pipeline emitted' do
        document = fixtures.wire_document(result)
        expect(document['json']).to eq(golden['json'])
        expect(document['leaf_types']).to eq(golden['leaf_types'])
      end

      it 'hands the serializer canonical entities and entries of the published types' do
        expected = pairs.filter_map { |pair| pair['entity'] }.flat_map do |entity|
          ["Ammitto::Ontology::Entities::#{entity.fetch('@type')}", 'Ammitto::Ontology::Sanction::SanctionEntry']
        end
        expect(result[:models].map { |model| model.class.name }).to eq(expected)
      end

      # Converting flat results afterwards would pass the class checks; the
      # transformer itself has to build canonical models
      it 'builds no flat model while transforming' do
        expect(result[:flat_constructions]).to eq({})
      end

      it 'reaches no model outside the canonical ontology' do
        flat = reachable.map { |model| model.class.name }.uniq.reject { |name| name.start_with?('Ammitto::Ontology::') }
        expect(flat).to eq([])
      end

      it 'reaches only sealed value objects' do
        unsealed = reachable.select(&value_object).reject(&sealed)
        expect(unsealed.map { |model| model.class.name }.uniq).to eq([])
      end
    end
  end

  # METI's transformer is not in the harmonize registry; the same contract
  # holds for it, driven directly.
  fixtures.extras.each do |extra|
    context "with #{extra['source']} #{extra['branch']}" do
      let(:result) { fixtures.run_extra(extra) }
      let(:golden) { JSON.parse(File.read(fixtures.golden_path(extra))) }
      let(:reachable) { fixtures.reachable_models(result[:models]) }
      let(:references) { ->(document) { document.dig('json', 'output', 'entity', 'sourceReferences') } }

      # The unmodified transformer passed its fetch time as fetched_at, a
      # keyword the flat SourceReference does not have, so the time never
      # reached the model; it is now kept, and is the only difference.
      it 'emits the JSON-LD the flat transformer emitted, plus the fetch time it dropped' do
        document = fixtures.wire_document(result)
        expect(references.call(document).map { |ref| ref.delete('retrievedAt') }).to eq(['2026-10-14T12:00:00Z'])
        document['leaf_types'].delete('$.output.entity.sourceReferences[0].retrievedAt')

        expect(document['json']).to eq(golden['json'])
        expect(document['leaf_types']).to eq(golden['leaf_types'])
      end

      it 'returns a canonical entity and entry' do
        expect(result[:models].map { |model| model.class.name })
          .to eq(%w[Ammitto::Ontology::Entities::OrganizationEntity Ammitto::Ontology::Sanction::SanctionEntry])
      end

      it 'builds no flat model while transforming' do
        expect(result[:flat_constructions]).to eq({})
      end

      it 'reaches no model outside the canonical ontology' do
        flat = reachable.map { |model| model.class.name }.uniq.reject { |name| name.start_with?('Ammitto::Ontology::') }
        expect(flat).to eq([])
      end

      it 'reaches only sealed value objects' do
        unsealed = reachable.select(&value_object).reject(&sealed)
        expect(unsealed.map { |model| model.class.name }.uniq).to eq([])
      end

      it 'keeps the legacy transform a flat projection of the same result' do
        legacy = fixtures.run_extra(extra, entrypoint: :transform)
        expect(legacy[:models].map { |model| model.class.name })
          .to eq(%w[Ammitto::OrganizationEntity Ammitto::SanctionEntry])
        expect(fixtures.wire_document(legacy)).to eq(fixtures.wire_document(result))
      end
    end
  end
end
