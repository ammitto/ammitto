# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_clamp_test') }
  let(:context_url) { 'https://www.ammitto.org/ontology/context.jsonld' }
  let(:exporter) do
    described_class.new(output_dir: output_dir, context_url: context_url)
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  def add_entry(exp, ref, identifiers)
    entity = {
      '@id' => "https://www.ammitto.org/entity/au/#{ref}",
      '@type' => 'PersonEntity'
    }
    entry = {
      '@id' => "https://www.ammitto.org/entry/au/consolidated/#{ref}",
      '@type' => 'SanctionEntry',
      'legalBases' => identifiers.map { |id| { 'identifier' => id } }
    }
    exp.add_node(entity: entity, entry: entry, source: :au)
  end

  def instrument_tails(exp)
    exp.instruments.keys.map { |id| id.split('/').last }
  end

  describe 'instrument slug clamping' do
    it 'clamps an oversized identifier to a 113-byte slug' do
      identifier = 'a' * 300
      add_entry(exporter, 'e1', [identifier])

      tail = instrument_tails(exporter).first
      digest = Digest::SHA256.hexdigest('a' * 300)[0, 12]
      expect(tail).to eq("#{'a' * 100}-#{digest}")
      expect(tail.bytesize).to eq(113)
    end

    it 'produces the same clamped IRI across independent runs' do
      identifier = "Long citation #{'x' * 400} end"

      first = described_class.new(output_dir: output_dir,
                                  context_url: context_url)
      second = described_class.new(output_dir: output_dir,
                                   context_url: context_url)
      add_entry(first, 'e1', [identifier])
      add_entry(second, 'e1', [identifier])

      expect(first.instruments.keys).to eq(second.instruments.keys)
    end

    it 'trims to a character boundary without splitting multibyte' do
      # legalCitations local_ids bypass normalize_identifier, so a
      # multibyte slug can reach the clamp. 100 three-byte chars =
      # 300 bytes; the 100-byte prefix cut lands mid-character and must
      # back up to 99 bytes (33 whole characters).
      local_id = '日' * 100
      entity = {
        '@id' => 'https://www.ammitto.org/entity/xx/m1',
        '@type' => 'PersonEntity'
      }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/xx/list/m1',
        '@type' => 'SanctionEntry',
        'legalCitations' => [
          {
            'legalInstrumentId' =>
              "https://www.ammitto.org/legal_instrument/xx/#{local_id}"
          }
        ]
      }
      exporter.add_node(entity: entity, entry: entry, source: :xx)

      tail = instrument_tails(exporter).first
      digest = Digest::SHA256.hexdigest(local_id)[0, 12]
      expect(tail).to eq("#{'日' * 33}-#{digest}")
      expect(tail).to be_valid_encoding
      expect(tail.bytesize).to eq(112)
    end

    it 'keeps identifiers sharing a 100-byte prefix distinct' do
      shared = 'p' * 260
      add_entry(exporter, 'e1', ["#{shared}alpha"])
      add_entry(exporter, 'e2', ["#{shared}omega"])

      tails = instrument_tails(exporter)
      expect(tails.length).to eq(2)
      expect(tails.uniq.length).to eq(2)
      expect(tails).to all(start_with("#{'p' * 100}-"))
    end

    it 'passes a short identifier through byte-identical' do
      add_entry(exporter, 'e1', ['unscr-1718'])

      expect(exporter.instruments.keys).to eq(
        ['https://www.ammitto.org/legal-instrument/au/unscr-1718']
      )
    end

    it 'leaves a slug exactly at the byte budget untouched' do
      at_budget = 'b' * 248
      add_entry(exporter, 'e1', [at_budget])

      expect(instrument_tails(exporter)).to eq([at_budget])
    end

    it 'merges distinct originals that normalize to one slug' do
      # Existing dedup semantics: whitespace/punctuation variants of the
      # same citation collapse to one instrument, clamped or not.
      add_entry(exporter, 'e1', ['UNSCR 1718', 'unscr--1718'])
      add_entry(exporter, 'e2', ["Act #{'z' * 300}", "act  #{'z' * 300}"])

      expect(exporter.instruments.length).to eq(2)
    end

    it 'raises loudly on a true clamped-slug collision' do
      allow(Digest::SHA256).to receive(:hexdigest).and_return('0' * 64)

      first = 'c' * 300
      second = 'c' * 301
      add_entry(exporter, 'e1', [first])

      expect { add_entry(exporter, 'e2', [second]) }
        .to raise_error(Ammitto::Error) { |error|
          expect(error.message).to include(first.inspect)
          expect(error.message).to include(second.inspect)
        }
    end

    it 'does not raise when the same identifier repeats' do
      identifier = 'd' * 300
      add_entry(exporter, 'e1', [identifier])

      expect { add_entry(exporter, 'e2', [identifier]) }.not_to raise_error
      expect(exporter.instruments.length).to eq(1)
    end

    it 'raises on citation-derived slugs spanning path components' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/au/e9',
        '@type' => 'PersonEntity'
      }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/au/consolidated/e9',
        '@type' => 'SanctionEntry',
        'legalCitations' => [{
          'legalInstrumentId' =>
            'https://www.ammitto.org/legal_instrument/au/../../escape/act-1'
        }]
      }

      expect { exporter.add_node(entity: entity, entry: entry, source: :au) }
        .to raise_error(Ammitto::Error, /unusable path component/)
    end

    it 'raises loudly when an identifier normalizes to an empty slug' do
      expect { add_entry(exporter, 'e8', ['///']) }
        .to raise_error(Ammitto::Error, /unusable path component/)
    end

    it 'raises on citation-derived sources escaping the node layout' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/au/e10',
        '@type' => 'PersonEntity'
      }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/au/consolidated/e10',
        '@type' => 'SanctionEntry',
        'legalCitations' => [{
          'legalInstrumentId' =>
            'https://www.ammitto.org/legal_instrument/../act-1'
        }]
      }

      expect { exporter.add_node(entity: entity, entry: entry, source: :au) }
        .to raise_error(Ammitto::Error, /unusable path component/)
    end

    it 'writes filenames equal to IRI tails for clamped and unclamped' do
      add_entry(exporter, 'e1', ['unscr-1718', 'a' * 300])
      exporter.export

      files = Dir.glob(
        File.join(output_dir, 'node', 'legal-instrument', 'au', '*.jsonld')
      )
      expect(files.length).to eq(2)

      files.each do |file|
        basename = File.basename(file, '.jsonld')
        expect(File.basename(file).bytesize).to be <= 255
        data = JSON.parse(File.read(file))
        expect(data['@id'].split('/').last).to eq(basename)
      end
    end
  end
end
