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
      'listed_date' => '2020-01-01', 'reference_number' => '1'
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

    it 'ignores a blank un_vessels row alias when canonical is set' do
      data = source_fixtures[:un_vessels].first
                                         .merge('designation_date' => '')

      result = transform(:un_vessels, data)
      expect(result[:entry]['period']['listedDate'])
        .to eq(Date.new(2021, 2, 3))
    end

    it 'prefers the canonical un_vessels date key over the row alias' do
      # Both keys present: the yaml mapping reads 'date_designated', so
      # from_hash has to resolve it the same way or the two parsers
      # disagree on a file carrying the fetch-time alias as well
      data = source_fixtures[:un_vessels].first
                                         .merge('designation_date' =>
                                                 '2024-01-01')

      result = transform(:un_vessels, data)
      expect(result[:entry]['period']['listedDate'])
        .to eq(Date.new(2021, 2, 3))
    end

    it 'keeps a blank canonical un_vessels date blank' do
      # A present-but-blank canonical key means "no date" — reaching
      # past it to the row alias would invent a date from_yaml, which
      # reads only the canonical key, would never produce
      data = source_fixtures[:un_vessels].first
                                         .merge('date_designated' => '',
                                                'designation_date' =>
                                                 '2024-01-01')

      result = transform(:un_vessels, data)
      expect(result[:entry]['period']['listedDate']).to be_nil
    end

    it 'routes a jp "individual" record to a person entity' do
      # Jp::Entity is the other model carrying a custom from_hash, and
      # its map_entity_type normalization only reaches harmonize now
      # that the round-trip is gone. The old from_yaml path handed the
      # transformer a raw "individual", which fell to the else branch
      # and filed a natural person as an organization.
      data = { 'id' => '1', 'name' => 'John Doe',
               'entity_type' => 'individual', 'addresses' => ['Tokyo'] }

      result = transform(:jp, data)
      expect(result[:entity]['entityType']).to eq('person')
    end

    it 'casts un_vessels integers the way the yaml path casts them' do
      # A bare to_i defeated the attribute's own Integer cast, turning a
      # grouped "12,500" tonnage into 12 — a plausible-looking number
      # invented from unparseable text
      data = source_fixtures[:un_vessels].first
                                         .merge('tonnage' => '12,500',
                                                'build_year' => '19x8')

      model = Ammitto::Sources::UnVessels::Vessel.from_hash(data)
      legacy = Ammitto::Sources::UnVessels::Vessel.from_yaml(data.to_yaml)

      expect(model.tonnage).to be_nil
      expect(model.build_year).to be_nil
      expect(model.tonnage).to eq(legacy.tonnage)
      expect(model.build_year).to eq(legacy.build_year)
    end
  end

  # The from_hash migration claims every converted call site accepts
  # exactly the shape from_yaml accepted. Asserting only that a
  # harmonized pair carries an @id would still pass if names, dates, or
  # nested collections were silently dropped — the very failure mode
  # this PR exists to remove — so compare the built models themselves.
  #
  # This differential is deliberately not the whole guarantee. A
  # key_value mapping governs from_hash AND from_yaml, so losing one
  # degrades both sides equally and stays invisible here; the two sites
  # that carry that risk (the uk wrapper mappings and the un_vessels
  # from_hash override) are pinned by value above, and dropping either
  # fails those examples.
  describe 'from_hash/from_yaml model equivalence' do
    # Capture the model the dispatcher actually built, without
    # duplicating its source-to-class branching here: stand a recorder
    # in for the transformer and keep the first argument it is handed.
    # Throwing unwinds the dispatcher the moment the model exists, so
    # nothing downstream of the transformer has to be simulated.
    def captured_model(source, data)
      recorder = Object.new
      recorder.define_singleton_method(:respond_to_missing?) do |*|
        true
      end
      recorder.define_singleton_method(:method_missing) do |_name, *args|
        throw :captured_model, args.first
      end
      allow(Ammitto::Transformers::Registry)
        .to receive(:get).and_return(recorder)

      catch(:captured_model) do
        command.send(:transform_data, source, data)
        nil
      end
    end

    source_fixtures.each do |source, fixtures|
      fixtures.each_with_index do |data, index|
        it "builds #{source} fixture #{index} the same either way" do
          model = captured_model(source, data)
          expect(model).not_to be_nil

          # Same class both ways: the only variable is the deserializer
          legacy = model.class.from_yaml(data.to_yaml)
          expect(model.to_yaml).to eq(legacy.to_yaml)
        end
      end
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

  # The two hand-written from_hash readers assign straight from the
  # hash, so they carry a check Lutaml performs for every other model.
  # Without it a container in a scalar slot survives, stringifies, and
  # sanitizes into an identifier indistinguishable from a real one —
  # the from_yaml path these readers replaced raised instead.
  describe 'containers in scalar slots are refused' do
    it 'does not let a jp list id collide with a scalar id' do
      # Both flatten to "jp-a-b": accepting the list would file two
      # distinct designees under one entity IRI
      scalar = transform(:jp, { 'id' => 'a-b', 'name' => 'X' })
      expect(scalar[:entity]['@id']).to end_with('/jp/jp-a-b')

      expect { transform(:jp, { 'id' => %w[a b], 'name' => 'X' }) }
        .to raise_error(ArgumentError, /id must hold a single value/)
    end

    it 'refuses a jp hash id' do
      expect { transform(:jp, { 'id' => { 'a' => 1 }, 'name' => 'X' }) }
        .to raise_error(ArgumentError, /id must hold a single value/)
    end

    # Every guarded slot gets its own example, so dropping fetch_scalar
    # from any single field fails the suite rather than hiding behind a
    # sibling field's coverage
    {
      jp: %w[id name name_ja entity_type source_url remarks],
      un_vessels: %w[id entity_type imo_number flag_state tonnage
                     build_year date_designated resolution]
    }.each do |source, fields|
      fields.each do |field|
        it "refuses a container in the #{source} #{field} slot" do
          data = source_fixtures[source].first.merge(field => %w[a b])

          expect { transform(source, data) }
            .to raise_error(ArgumentError,
                            /#{field} must hold a single value/)
        end
      end
    end

    it 'refuses the un_vessels row alias when canonical is absent' do
      # The alias is only consulted when the canonical key is missing,
      # so its guard needs the canonical key genuinely absent
      data = source_fixtures[:un_vessels].first
                                         .except('date_designated')
                                         .merge('designation_date' => %w[a b])

      expect { transform(:un_vessels, data) }
        .to raise_error(ArgumentError,
                        /designation_date must hold a single value/)
    end

    # The guard must reject containers only: every scalar YAML scalar
    # type still has to build a record, or it would reject real data
    it 'still accepts every scalar id type' do
      { 'a-b' => 'jp-a-b', 123 => 'jp-123', 1.5 => 'jp-15',
        true => 'jp-true' }.each do |id, expected|
        result = transform(:jp, { 'id' => id, 'name' => 'X' })
        expect(result[:entity]['@id']).to end_with("/jp/#{expected}")
      end
    end

    it 'leaves the real collection fields alone' do
      result = transform(:jp, { 'id' => '1', 'name' => 'X',
                                'addresses' => %w[Tokyo Osaka] })

      expect(result[:entity]['@id']).to end_with('/jp/jp-1')
      expect(result[:entity]['addresses'].map { |a| a['street'] })
        .to eq(%w[Tokyo Osaka])
    end

    # Deliberate, and the one place from_hash is MORE permissive than
    # the from_yaml path it replaced: a lone scalar address used to
    # reach Jp::Transformer as a bare String and crash it on #map.
    # Reading it as a one-element list is the only sensible meaning, it
    # loses no record and collides with nothing, so harmonize now
    # accepts the file the old path merely failed on.
    it 'reads a lone scalar address as a one-element list' do
      result = transform(:jp, { 'id' => '1', 'name' => 'X',
                                'addresses' => 'Tokyo' })

      expect(result[:entity]['addresses'].map { |a| a['street'] })
        .to eq(['Tokyo'])
    end
  end

  describe 'blank local ids raise instead of collapsing to "unknown"' do
    # tr is the one source with a documented empty-reference case, so a
    # blank reference falls back to the name; only an unusable name raises.
    it 'fails the tr path loudly when reference and name are both unusable' do
      data = source_fixtures[:tr].first
                                 .merge('reference_number' => nil, 'name' => '  ')

      expect { transform(:tr, data) }.to raise_error(
        Ammitto::Utils::IriSanitizer::MissingLocalIdError,
        /tr: cannot build entity IRI from blank or unusable local id/
      )
    end

    it 'uses the name when tr publishes no reference' do
      data = source_fixtures[:tr].first.merge('reference_number' => nil)

      result = transform(:tr, data)
      pair = result.is_a?(Array) ? result.first : result
      expect(pair[:entity]['@id']).to match(%r{/entity/tr/acme\z})
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

    # Turkey leaves the Sira No cell empty on 37 of its rows. Those records
    # take a deterministic name-derived id rather than raising, so the slice
    # completes; a record with neither a usable reference nor a usable name
    # still raises.
    it 'gives a tr record with no reference a name-derived id (end to end)' do
      Dir.mktmpdir do |dir|
        processed = File.join(dir, 'data-tr', 'processed')
        FileUtils.mkdir_p(processed)
        File.write(File.join(processed, 'tr-1.yaml'),
                   source_fixtures[:tr].first
                     .merge('reference_number' => nil).to_yaml)

        options = { sources_dir: dir,
                    output_dir: File.join(dir, 'api', 'v1') }
        expect { Ammitto::Cmd::HarmonizeCommand.new(options, ['tr']).run }
          .not_to raise_error

        graph = JSON.parse(
          File.read(File.join(dir, 'api', 'v1', 'sources', 'tr.jsonld'))
        )['@graph']
        ids = graph.map { |n| n['@id'] }.compact
        expect(ids).to include(a_string_matching(%r{/entity/tr/acme\z}))
        expect(ids).not_to include(a_string_matching(%r{/entity/tr/unknown\z}))
      end
    end

    it 'still fails a tr record with neither reference nor usable name' do
      Dir.mktmpdir do |dir|
        processed = File.join(dir, 'data-tr', 'processed')
        FileUtils.mkdir_p(processed)
        File.write(File.join(processed, 'tr-1.yaml'),
                   source_fixtures[:tr].first
                     .merge('reference_number' => nil, 'name' => '  ').to_yaml)

        options = { sources_dir: dir,
                    output_dir: File.join(dir, 'api', 'v1') }
        expect { Ammitto::Cmd::HarmonizeCommand.new(options, ['tr']).run }
          .to raise_error(Thor::Error,
                          /tr-1\.yaml: tr: cannot build entity IRI/)
      end
    end
  end

  describe 'unparseable YAML is a per-file error, not a source error' do
    run_with = lambda do |dir, extra|
      processed = File.join(dir, 'data-tr', 'processed')
      FileUtils.mkdir_p(processed)
      File.write(File.join(processed, 'ok.yaml'),
                 source_fixtures[:tr].first.to_yaml)
      File.write(File.join(processed, 'broken.yaml'), "a:\n  - [unterminated\n")

      options = { sources_dir: dir,
                  output_dir: File.join(dir, 'api', 'v1') }.merge(extra)
      Ammitto::Cmd::HarmonizeCommand.new(options, ['tr']).run
    end

    it 'attributes the parse failure to its file and keeps the good ones' do
      Dir.mktmpdir do |dir|
        expect { run_with.call(dir, {}) }
          .to raise_error(Thor::Error, /broken\.yaml/)
      end
    end

    it 'is not cleared by --allow-empty (per-file errors never are)' do
      Dir.mktmpdir do |dir|
        expect { run_with.call(dir, allow_empty: 'tr') }
          .to raise_error(Thor::Error,
                          /tr: 1 file\(s\) failed to transform/)
      end
    end
  end
end
