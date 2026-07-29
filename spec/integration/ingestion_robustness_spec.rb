# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'date'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

%w[uk/designation eu/sanction_entity un/individual un/entity us/sdn_entry
   wb/sanctioned_firm au/sanctions_list ca/sanctions_list ch/sanctions_list
   ru/sanctions_list nz/sanctions_list tr/sanctions_list eu_vessels/vessel
   jp/entity un_vessels/vessel].each { |f| require "ammitto/sources/#{f}" }

# Ingestion robustness: every per-entity source path must survive YAML
# anchors in its input (no from_yaml(data.to_yaml) round-trip through the
# aliases-disabled Lutaml loader), announcement-format YAML must be
# rejected loudly on the legacy ch/us/uk paths, and records without a
# usable local id must raise instead of collapsing into a shared
# ".../unknown" IRI.
RSpec.describe 'harmonize ingestion robustness (integration)' do
  # Minimal fetch-shaped data per source path, keyed by the dispatch
  # source symbol. Multi-model sources (un, au, nz) carry one fixture
  # per model branch.
  source_fixtures = {
    uk: [{
      'unique_id' => 'UK0001', 'regime_name' => 'Russia',
      'individual_entity_ship' => 'Individual',
      'names' => { 'names' => [{ 'name6' => 'John Doe',
                                 'name_type' => 'Primary Name' }] }
    }],
    eu: [{
      'logical_id' => '55', 'eu_reference_number' => 'EU.55',
      'subject_type' => { 'code' => 'person' },
      'name_aliases' => [{ 'whole_name' => 'John Doe' }],
      'birthdates' => [{ 'birthdate' => '1964-07-17' }]
    }],
    un: [
      { 'dataid' => '123', 'reference_number' => 'QDi.001',
        'first_name' => 'John', 'second_name' => 'Doe',
        'gender' => 'male', 'listed_on' => '2001-10-08' },
      { 'dataid' => '124', 'reference_number' => 'QDe.001',
        'first_name' => 'ACME CORP', 'listed_on' => '2001-10-08' }
    ],
    us: [{
      'uid' => '12345', 'first_name' => 'John', 'last_name' => 'DOE',
      'sdn_type' => 'Individual'
    }],
    wb: [{
      'supp_id' => 100, 'supp_name' => 'ACME LTD',
      'entity_type' => 'organization', 'country_name' => 'Utopia',
      'debar_from_date' => Date.new(2020, 1, 2),
      'debar_to_date' => '2025-01-02'
    }],
    au: [
      { 'reference' => '7', 'imo_number' => 'IMO 12345',
        'names' => [{ 'text' => 'SHIP X', 'name_type' => 'primary' }] },
      { 'reference' => '8577', 'dates_of_birth' => [],
        'names' => [{ 'text' => 'John Doe', 'name_type' => 'primary' }] },
      { 'reference' => '9000',
        'names' => [{ 'text' => 'ACME', 'name_type' => 'primary' }] }
    ],
    ca: [{
      'country' => 'Iran', 'schedule' => '1', 'item' => '5',
      'last_name' => 'DOE', 'given_name' => 'John',
      'entity_type' => 'person', 'date_of_listing' => '2020-01-01'
    }],
    ch: [{
      'ssid' => '111',
      'names' => [{ 'name_parts' => [
        { 'name_part_type' => 'given-name', 'value' => 'Vladimir' },
        { 'name_part_type' => 'family-name', 'value' => 'Testov' }
      ] }]
    }],
    ru: [{
      'russian_name' => 'Иванов', 'english_name' => 'Ivanov',
      'entity_type' => 'person', 'announcement_number' => '123',
      'list_type' => 'stop_list'
    }],
    nz: [
      { 'type' => 'Individual', 'unique_identifier' => 'IND-001' },
      { 'type' => 'Ship', 'unique_identifier' => 'SHP-001',
        'imo_number' => '999', 'name' => 'SHIP Y',
        'date_of_sanction' => Date.new(2022, 3, 4) },
      { 'type' => 'Entity', 'unique_identifier' => 'ENT-001',
        'name' => 'ACME' }
    ],
    tr: [{
      'name' => 'ACME', 'entity_type' => 'Entity', 'program' => '6415',
      'listed_date' => '2020-01-01', 'reference_number' => 'TR-1'
    }],
    eu_vessels: [{
      'vessel_name' => 'SHIP Z', 'imo_number' => '12345',
      'date_of_application' => Date.new(2024, 5, 6)
    }],
    jp: [{
      'id' => '1', 'name' => 'ACME', 'entity_type' => 'organization',
      'addresses' => ['Tokyo']
    }],
    un_vessels: [{
      'id' => 'V1', 'imo_number' => '456',
      'names' => [{ 'full_name' => 'SHIP W', 'is_primary' => true }],
      'date_designated' => Date.new(2021, 2, 3), 'resolution' => 'RES 1'
    }]
  }.freeze

  announcement_data = {
    'announcement' => { 'id' => 'mofcom-2026-11',
                        'date' => '2026-11-01' },
    'sanction_details' => { 'entities' => [{ 'name' => 'ACME' }] }
  }.freeze

  let(:exporter_dir) { Dir.mktmpdir('ammitto_ingestion_robustness') }
  let(:command) { Ammitto::Cmd::HarmonizeCommand.new({}, []) }

  before do
    command.instance_variable_set(
      :@exporter,
      Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: exporter_dir)
    )
  end

  after do
    FileUtils.rm_rf(exporter_dir)
  end

  def transform(source, data)
    command.send(:transform_data, source, data)
  end

  def expect_complete_pair(result)
    pair = result.is_a?(Array) ? result.first : result
    expect(pair[:entity]).to include('@id')
    expect(pair[:entry]).to include('@id')
  end

  # A hash shared between two keys re-emits YAML anchors on any
  # to_yaml re-dump — exactly what jp harvest files carry after
  # YAML.safe_load_file(..., aliases: true). The old
  # from_yaml(data.to_yaml) round-trip fed those anchors back into the
  # aliases-disabled Lutaml loader (Psych::AliasesNotEnabled).
  def with_anchor(data)
    shared = { 'shared' => 'anchored block' }
    data.merge('anchored_a' => shared, 'anchored_b' => shared)
  end

  describe 'anchored-YAML round-trip immunity' do
    source_fixtures.each do |source, fixtures|
      fixtures.each_with_index do |data, index|
        it "harmonizes #{source} fixture #{index} with YAML anchors" do
          anchored = with_anchor(data)
          # Sanity: the fixture genuinely re-emits an alias when dumped
          expect(anchored.to_yaml).to include('*')

          expect_complete_pair(transform(source, anchored))
        end
      end
    end

    it 'parses an alias-consuming mapped field through the hash path' do
      # The consumed name_parts array IS the aliased node (*p): loading
      # yields one shared array object, so any to_yaml re-dump re-emits
      # the anchor — the exact shape that killed the old round-trip
      data = YAML.safe_load(<<~YAML, aliases: true)
        ssid: '111'
        shared_parts: &p
          - name_part_type: given-name
            value: Vladimir
          - name_part_type: family-name
            value: Testov
        names:
          - name_parts: *p
      YAML
      expect(data.to_yaml).to include('*') # genuinely re-anchored

      result = transform(:ch, data)
      expect(result[:entity]['names'].first['fullName'])
        .to include('Vladimir')
    end

    it 'preserves uk wrapper-mapped names through the hash path' do
      result = transform(:uk, with_anchor(source_fixtures[:uk].first))

      expect(result[:entity]['names'].map { |n| n['fullName'] })
        .to include('John Doe')
    end

    it 'preserves un_vessels names and designation date' do
      result = transform(:un_vessels,
                         with_anchor(source_fixtures[:un_vessels].first))

      expect(result[:entity]['names'].map { |n| n['fullName'] })
        .to include('SHIP W')
      expect(result[:entry]['period']['listedDate'])
        .to eq(Date.new(2021, 2, 3))
    end

    it 'accepts the un_vessels fetch-time date key too' do
      data = source_fixtures[:un_vessels].first.dup
      data.delete('date_designated')
      data['designation_date'] = '2021-02-03'

      result = transform(:un_vessels, data)
      expect(result[:entry]['period']['listedDate'])
        .to eq(Date.new(2021, 2, 3))
    end

    it 'falls past a blank un_vessels date key to the serialized one' do
      data = source_fixtures[:un_vessels].first
                                         .merge('designation_date' => '')

      result = transform(:un_vessels, data)
      expect(result[:entry]['period']['listedDate'])
        .to eq(Date.new(2021, 2, 3))
    end
  end

  # Au::Transformer#transform_from_hash is a second, independent entry
  # point (external callers reach it directly, not through
  # HarmonizeCommand#transform_au), so its three model constructions
  # need their own anchored coverage.
  describe 'Au::Transformer#transform_from_hash' do
    let(:transformer) { Ammitto::Sources::Au::Transformer.new }

    {
      'person' => { 'type' => 'person', 'reference' => '8577',
                    'names' => [{ 'text' => 'John Doe',
                                  'name_type' => 'primary' }] },
      'vessel' => { 'type' => 'vessel', 'reference' => '7',
                    'imo_number' => 'IMO 12345',
                    'names' => [{ 'text' => 'SHIP X',
                                  'name_type' => 'primary' }] },
      'organization' => { 'reference' => '9000',
                          'names' => [{ 'text' => 'ACME',
                                        'name_type' => 'primary' }] }
    }.each do |kind, data|
      it "transforms an anchored #{kind} hash" do
        anchored = with_anchor(data)
        expect(anchored.to_yaml).to include('*') # genuinely re-anchored

        result = transformer.transform_from_hash(anchored)

        expect(result[:entity].id).to include('entity/au/')
        expect(result[:entry].id).to include('entry/au/')
      end
    end
  end

  # The from_hash migration must not widen any mapping block beyond the
  # format it already covered. UnVessels::Vessel declares only a yaml
  # block, so JSON keeps the attribute-name key 'designation_date';
  # converting it to key_value would silently repoint JSON at
  # 'date_designated' and break existing payloads.
  describe 'un_vessels JSON contract' do
    let(:vessel) do
      Ammitto::Sources::UnVessels::Vessel.new.tap do |v|
        v.id = 'V1'
        v.imo_number = '456'
        v.designation_date = Date.new(2021, 2, 3)
      end
    end

    it 'still emits the attribute-name JSON key' do
      expect(JSON.parse(vessel.to_json)).to include(
        'designation_date' => '2021-02-03'
      )
    end

    it 'still parses the attribute-name JSON key' do
      parsed = Ammitto::Sources::UnVessels::Vessel.from_json(
        { 'id' => 'V1', 'designation_date' => '2021-02-03' }.to_json
      )

      expect(parsed.designation_date).to eq(Date.new(2021, 2, 3))
    end

    it 'still maps the YAML key to the same attribute' do
      parsed = Ammitto::Sources::UnVessels::Vessel.from_yaml(
        { 'id' => 'V1', 'date_designated' => '2021-02-03' }.to_yaml
      )

      expect(parsed.designation_date).to eq(Date.new(2021, 2, 3))
    end
  end

  describe 'announcement-format guards (ch/us/uk)' do
    %i[ch us uk].each do |source|
      it "rejects announcement-format YAML on the #{source} path" do
        expect { transform(source, announcement_data) }
          .to raise_error(
            Ammitto::Cmd::HarmonizeCommand::AnnouncementFormatError,
            /announcement-format YAML detected.*#{source}/m
          )
      end

      it "keeps correct-schema #{source} input working" do
        expect_complete_pair(transform(source, source_fixtures[source].first))
      end
    end

    %w[announcement sanction_details measure_modifications].each do |marker|
      it "rejects a lone #{marker} marker key" do
        expect { transform(:ch, { marker => { 'id' => 'x' } }) }
          .to raise_error(
            Ammitto::Cmd::HarmonizeCommand::AnnouncementFormatError,
            /top-level #{marker}\b/
          )
      end
    end

    it 'fails the run non-zero with per-file attribution (end to end)' do
      Dir.mktmpdir do |dir|
        processed = File.join(dir, 'data-ch', 'processed')
        FileUtils.mkdir_p(processed)
        File.write(File.join(processed, '20261101.yaml'),
                   announcement_data.to_yaml)

        options = { sources_dir: dir,
                    output_dir: File.join(dir, 'api', 'v1') }
        expect { Ammitto::Cmd::HarmonizeCommand.new(options, ['ch']).run }
          .to raise_error(Thor::Error,
                          /20261101\.yaml: announcement-format YAML detected/)
      end
    end
  end

  describe 'blank local ids raise instead of collapsing to "unknown"' do
    it 'fails the tr path loudly for a record without reference_number' do
      data = source_fixtures[:tr].first.merge('reference_number' => nil)

      expect { transform(:tr, data) }.to raise_error(
        Ammitto::Utils::IriSanitizer::MissingLocalIdError,
        /tr: cannot build entity IRI from blank or unusable local id/
      )
    end

    it 'fails the jp path loudly for a record without id' do
      data = source_fixtures[:jp].first.merge('id' => nil)

      expect { transform(:jp, data) }.to raise_error(
        Ammitto::Utils::IriSanitizer::MissingLocalIdError,
        /jp: cannot build entity IRI from blank or unusable local id/
      )
    end

    it 'fails the jp path for a punctuation-only id (the jp/jp trap)' do
      # "JP-!!!" would sanitize to the constant "jp" and collapse into
      # entity/jp/jp; the unusable id must raise instead
      data = source_fixtures[:jp].first.merge('id' => '!!!')

      expect { transform(:jp, data) }.to raise_error(
        Ammitto::Utils::IriSanitizer::MissingLocalIdError, /jp:/
      )
    end

    it 'fails the us path loudly for an SDN record without uid' do
      data = source_fixtures[:us].first.merge('uid' => nil)

      expect { transform(:us, data) }.to raise_error(
        Ammitto::Utils::IriSanitizer::MissingLocalIdError,
        /us: cannot build entity IRI from blank or unusable local id/
      )
    end

    it 'fails the whole tr slice at the health gate (end to end)' do
      Dir.mktmpdir do |dir|
        processed = File.join(dir, 'data-tr', 'processed')
        FileUtils.mkdir_p(processed)
        File.write(File.join(processed, 'tr-1.yaml'),
                   source_fixtures[:tr].first
                     .merge('reference_number' => nil).to_yaml)

        options = { sources_dir: dir,
                    output_dir: File.join(dir, 'api', 'v1') }
        expect { Ammitto::Cmd::HarmonizeCommand.new(options, ['tr']).run }
          .to raise_error(Thor::Error,
                          /tr-1\.yaml: tr: cannot build entity IRI/)
      end
    end
  end
end
