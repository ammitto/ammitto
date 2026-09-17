# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Cmd::Harmonize::SourceTransforms do
  # Exercised through a HarmonizeCommand instance, which includes this
  # module via MultiShapeSourceTransforms: the module has no meaning without
  # the command that supplies @exporter and the transformer-registry lookup
  # around it.
  #
  # Only the '#transform_jp with an announcement that carries no ids'
  # context below constructs a command with sources_dir set; the others
  # pass {} and never touch disk.
  let(:command_options) { {} }

  subject(:command) { Ammitto::Cmd::HarmonizeCommand.new(command_options, [source_code]) }

  # `fetch(0)` rather than `first`: the constructor does not reject an empty
  # source list, the guard for that is #run's emptiness raise, and these
  # examples call #transform_data directly. `first` would hand
  # transform_data a nil source and return { entity: nil, entry: nil }, which
  # fails somewhere later and harder. `fetch(0)` raises here instead.
  #
  # Index 0 is the right element because those three subjects each pass a
  # single-element array. That is not general: `normalize_sources` expands the
  # list under --scan and --all, and an explicit multi-source array stays
  # multi-source.
  def harmonize(record)
    command.send(:transform_data, command.sources.fetch(0), record)
  end

  describe '#transform_jp with an announcement that carries no ids' do
    include HarmonizeSourcesDir

    # data-jp's fefta-list/20250131.yml is a whole list — 748 records —
    # published without a single `id`. Every other data-jp announcement
    # writes its ids by hand as jp.<authority>.<list>.<position>, and
    # reuses them verbatim in each later dated file for the same list.
    let(:command_options) { { sources_dir: sources_dir } }
    let(:source_code) { 'jp' }

    let(:transformer) do
      Ammitto::Transformers::Registry.get(:jp)
    end

    let(:announcement) do
      {
        'announcement' => {
          'authority' => 'jp/meti',
          'type' => 'jp/fefta-end-user-list-announcement',
          'url' => 'https://www.meti.go.jp/policy/anpo/index.html'
        },
        'sanction_details' => {
          'entities' => [
            { 'name' => { 'en' => 'First Org' }, 'type' => 'organization',
              'sanction_list' => 'jp/fefta-end-user-list' },
            { 'name' => { 'en' => 'Second Org' }, 'type' => 'organization',
              'sanction_list' => 'jp/fefta-end-user-list' }
          ]
        }
      }
    end

    it 'publishes every record instead of refusing the whole file' do
      results = command.send(:transform_jp, transformer, announcement)

      expect(results.map { |r| r[:entity]['names'].first['fullName'] })
        .to eq(['First Org', 'Second Org'])
    end

    it 'mints positional ids in the convention the list already uses' do
      results = command.send(:transform_jp, transformer, announcement)

      expect(results.map { |r| r[:entity]['@id'] }).to eq(
        %w[
          https://www.ammitto.org/entity/jp/jp-jpmetifefta-end-user-list1
          https://www.ammitto.org/entity/jp/jp-jpmetifefta-end-user-list2
        ]
      )
    end

    it 'keeps an explicit id in preference to a minted one' do
      announcement['sanction_details']['entities'][0]['id'] =
        'jp.meti.fefta.77'

      results = command.send(:transform_jp, transformer, announcement)

      expect(results.first[:entity]['@id'])
        .to eq('https://www.ammitto.org/entity/jp/jp-jpmetifefta77')
    end

    it 'numbers by entry_number when the record carries one' do
      announcement['sanction_details']['entities'][1]['entry_number'] = 42

      results = command.send(:transform_jp, transformer, announcement)

      expect(results.last[:entity]['@id'])
        .to eq('https://www.ammitto.org/entity/jp/jp-jpmetifefta-end-user-list42')
    end
  end

  # Enters at Cmd::HarmonizeCommand#transform_data, so the assertions cover the
  # transformer-registry lookup and the :tr routing branch as well as the
  # transformation and its JSON-LD serialization. Input is the parsed shape of a
  # record file the fetcher committed to data-tr.
  context 'with a tr record' do
    let(:source_code) { :tr }

    let(:numbered) do
      { 'name' => 'YUN HO-JIN',
        'entity_type' => 'person',
        'program' => 'Law No. 7262, Articles 3.A/3.B',
        'listed_date' => '24.2.2021/ 3578',
        'reference_number' => '1' }
    end

    let(:unnumbered) do
      { 'name' => 'DAWOOD AGHA-JANI',
        'entity_type' => 'person',
        'program' => 'Law No. 7262, Articles 3.A/3.B',
        'place_of_birth' => 'Ardebil, İran' }
    end

    describe '#transform_data' do
      it 'keeps the numbered record on its published IRI' do
        expect(harmonize(numbered)[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/tr/1')
      end

      it 'gives the unnumbered record its own IRI, not the placeholder' do
        expect(harmonize(unnumbered)[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/tr/dawood-agha-jani')
      end

      it 'does not let the unnumbered record collide with a numbered one' do
        expect(harmonize(unnumbered)[:entity]['@id'])
          .not_to eq(harmonize(numbered)[:entity]['@id'])
      end

      it 'points the serialized entry at the same entity' do
        result = harmonize(unnumbered)

        expect(result[:entry]['@id']).to end_with('/dawood-agha-jani')
        expect(result[:entry]['entityId']).to eq(result[:entity]['@id'])
      end

      it 'emits no reference number for a record Turkey did not number' do
        reference = harmonize(unnumbered)[:entity]['sourceReferences'].first

        expect(reference['sourceCode']).to eq('tr')
        expect(reference).not_to have_key('referenceNumber')
      end

      it 'still emits the reference number Turkey did publish' do
        reference = harmonize(numbered)[:entity]['sourceReferences'].first

        expect(reference['referenceNumber']).to eq('1')
      end

      it 'routes an unnumbered record to its own name-derived entity' do
        other = unnumbered.merge('name' => 'AMIR MOAYYED ALAI')

        expect(harmonize(other)[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/tr/amir-moayyed-alai')
        expect(harmonize(other)[:entity]['@id'])
          .not_to eq(harmonize(unnumbered)[:entity]['@id'])
      end
    end
  end

  # Enters at Cmd::HarmonizeCommand#transform_data, covering the :ch
  # routing branch. Input is the parsed shape `fetch ch` commits to
  # data-ch/processed: Ch::SanctionsList#all_identities returns the
  # parsed <target> elements, so every committed record is a target
  # wrapper, not the bare <identity> the branch's comment described.
  context 'with a ch record' do
    let(:source_code) { :ch }
    let(:identity_body) do
      { 'ssid' => '100189',
        'main' => 'true',
        'names' => [{ 'name_type' => 'primary-name', 'quality' => 'good',
                      'lang' => 'eng', 'name_parts' => name_parts }],
        'day_month_year' => { 'day' => 24, 'month' => 11,
                              'year' => 1945 } }
    end
    let(:target) do
      { 'ssid' => '100187',
        'sanctions_set_id' => '8174',
        'individual' => { 'identity' => identity_body,
                          'justification' => 'Former Deputy Head of AEOI.' } }
    end

    def name_parts
      [{ 'order' => 1, 'name_part_type' => 'family-name',
         'value' => 'Khalilipour' },
       { 'order' => 2, 'name_part_type' => 'given-name',
         'value' => 'Said Esmail' }]
    end

    describe '#transform_data' do
      it 'names the person a target-shaped record wraps' do
        entity = harmonize(target)[:entity]

        expect(entity['names'].first['fullName'])
          .to eq('Khalilipour Said Esmail')
      end

      it 'keys the entity on the target ssid, not the identity ssid' do
        expect(harmonize(target)[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/ch/100187')
      end

      it 'types a target wrapping an individual as a person' do
        expect(harmonize(target)[:entity]['entityType']).to eq('person')
      end

      it 'types a target wrapping an entity as an organization' do
        org = { 'ssid' => '200000', 'sanctions_set_id' => '1',
                'entity' => { 'identity' => identity_body } }

        expect(harmonize(org)[:entity]['entityType']).to eq('organization')
      end

      it 'still transforms a bare identity record' do
        expect(harmonize(identity_body)[:entity]['names'].first['fullName'])
          .to eq('Khalilipour Said Esmail')
      end
    end
  end

  # Enters at Cmd::HarmonizeCommand#transform_data, covering the :jp
  # routing branch. `fetch jp` writes no per-entity YAML (the source is
  # a PDF), so discovery always reaches data-jp's announcement files
  # under sources/sanction-lists — in two shapes, one with entities at
  # the top level and one with them under sanction_details.
  context 'with a jp announcement file' do
    let(:source_code) { :jp }
    let(:identified) do
      { 'announcement' => header,
        'entities' => [
          { 'id' => 'jp.mofa.belarus.2', 'entry_number' => 2,
            'name' => { 'ja' => '株式会社インテグラル',
                        'en' => 'JSC Integral' },
            'type' => 'organization',
            'sanction_list' => 'jp/belarus-export-prohibition-list' }
        ] }
    end
    let(:unidentified) do
      { 'announcement' => header.merge('authority' => 'jp/meti'),
        'sanction_details' => {
          'entities' => [
            { 'name' => { 'en' => "Al Qa'ida/Islamic Army" },
              'type' => 'organization',
              'sanction_list' => 'jp/fefta-end-user-list',
              'reason' => [{ 'en' => 'Involved in chemical weapons' }] },
            { 'name' => { 'ja' => 'アフガニスタン国防省' },
              'type' => 'organization',
              'sanction_list' => 'jp/fefta-end-user-list' }
          ]
        } }
    end

    def header
      { 'title' => [{ 'en' => 'Belarus Export Prohibition' }],
        'publish_date' => '2022-03-15',
        'authority' => 'jp/mofa',
        'type' => 'jp/export-prohibition-announcement',
        'source_url' => 'https://www.mofa.go.jp/mofaj/files/100312394.pdf' }
    end

    describe '#transform_data' do
      it 'returns one result per entity of a top-level announcement' do
        expect(harmonize(identified).length).to eq(1)
      end

      it 'keeps a published id on its own IRI' do
        expect(harmonize(identified).first[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/jp/jp-jpmofabelarus2')
      end

      it 'prefers the English name and keeps the Japanese one' do
        entity = harmonize(identified).first[:entity]

        expect(entity['names'].first['fullName']).to eq('JSC Integral')
      end

      it 'reads entities nested under sanction_details' do
        expect(harmonize(unidentified).length).to eq(2)
      end

      it 'derives an IRI for a record the source did not identify' do
        expect(harmonize(unidentified).first[:entity]['@id'])
          .to eq('https://www.ammitto.org/entity/jp/' \
                 'jp-jpmetifefta-end-user-list1')
      end

      it 'keeps two unidentified records on distinct IRIs' do
        ids = harmonize(unidentified).map { |r| r[:entity]['@id'] }

        expect(ids.uniq.length).to eq(2)
      end

      it 'carries the announcement source url onto the entry' do
        entry = harmonize(identified).first[:entry]

        expect(entry['entityId'])
          .to eq(harmonize(identified).first[:entity]['@id'])
      end

      it 'keeps both remarks and reason when a record carries both' do
        both = { 'announcement' => header,
                 'entities' => [
                   { 'id' => 'jp.meti.9', 'name' => { 'en' => 'Both Co' },
                     'type' => 'organization',
                     'remarks' => [{ 'en' => 'Listed 2024.' }],
                     'reason' => [{ 'en' => 'Missile programme.' }] }
                 ] }

        expect(harmonize(both).first[:entity]['remarks'])
          .to eq('Listed 2024. Missile programme.')
      end

      it 'still transforms a flat per-entity record' do
        flat = { 'id' => 'jp.meti.1', 'name' => 'Flat Record',
                 'entity_type' => 'organization' }

        expect(harmonize(flat)[:entity]['names'].first['fullName'])
          .to eq('Flat Record')
      end
    end
  end
end
