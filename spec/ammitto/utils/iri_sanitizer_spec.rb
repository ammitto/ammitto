# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Utils::IriSanitizer do
  describe '::BASE_URI' do
    it 'returns the base URI' do
      expect(described_class::BASE_URI).to eq('https://www.ammitto.org')
    end
  end

  describe '.sanitize' do
    context 'with valid input' do
      it 'converts to lowercase' do
        expect(described_class.sanitize('Mitsubishi Heavy Industries')).to eq('mitsubishi-heavy-industries')
      end

      it 'replaces whitespace with hyphens' do
        expect(described_class.sanitize('Some Name')).to eq('some-name')
      end

      it 'replaces multiple spaces with single hyphen' do
        expect(described_class.sanitize('Some   Name')).to eq('some-name')
      end

      it 'removes special characters' do
        expect(described_class.sanitize("O'Brien & Co.")).to eq('obrien-co')
      end

      it 'collapses multiple hyphens' do
        expect(described_class.sanitize('Some--Name')).to eq('some-name')
      end

      it 'removes leading hyphens' do
        expect(described_class.sanitize('-Some Name')).to eq('some-name')
      end

      it 'removes trailing hyphens' do
        expect(described_class.sanitize('Some Name-')).to eq('some-name')
      end

      it 'truncates to MAX_ID_LENGTH characters' do
        long_string = 'a' * 100
        result = described_class.sanitize(long_string)
        expect(result.length).to eq(64)
      end

      it 'handles mixed case and spaces' do
        expect(described_class.sanitize('  Some   NAME -- Test  ')).to eq('some-name-test')
      end
    end

    context 'with nil or empty input' do
      it 'returns "unknown" for nil' do
        expect(described_class.sanitize(nil)).to eq('unknown')
      end

      it 'returns "unknown" for empty string' do
        expect(described_class.sanitize('')).to eq('unknown')
      end

      it 'returns "unknown" for whitespace-only string' do
        expect(described_class.sanitize('   ')).to eq('unknown')
      end

      it 'returns "unknown" when result is empty after sanitization' do
        expect(described_class.sanitize('!!!')).to eq('unknown')
      end
    end

    context 'with numeric input' do
      it 'handles integers' do
        expect(described_class.sanitize(12_345)).to eq('12345')
      end

      it 'handles symbols by converting to string (preserves underscores)' do
        expect(described_class.sanitize(:some_symbol)).to eq('some_symbol')
      end
    end
  end

  describe 'blank local ids' do
    it 'raises MissingLocalIdError for a nil entity local id' do
      expect { described_class.entity_iri('tr', nil) }.to raise_error(
        described_class::MissingLocalIdError,
        /tr: cannot build entity IRI from blank or unusable local id nil/
      )
    end

    it 'raises for an empty or whitespace-only local id' do
      expect { described_class.entity_iri('tr', '') }
        .to raise_error(described_class::MissingLocalIdError)
      expect { described_class.entity_iri('tr', '   ') }
        .to raise_error(described_class::MissingLocalIdError)
    end

    it 'raises for a local id that sanitizes to an empty string' do
      expect { described_class.entity_iri('us', '!!!') }.to raise_error(
        described_class::MissingLocalIdError,
        /us: cannot build entity IRI from blank or unusable local id "!!!"/
      )
    end

    it 'converts a local id to a string exactly once' do
      # #to_s may be heavyweight (an Array id materializes its whole
      # contents) and reaches this method straight from parsed YAML,
      # so neither the accepted nor the rejected path may convert twice
      counter = Class.new do
        attr_reader :calls

        def initialize(text)
          @text = text
          @calls = 0
        end

        def to_s
          @calls += 1
          @text
        end
      end

      accepted = counter.new('abc-123')
      expect(described_class.entity_iri('tr', accepted))
        .to eq('https://www.ammitto.org/entity/tr/abc-123')
      expect(accepted.calls).to eq(1)

      rejected = counter.new('!!!')
      expect { described_class.entity_iri('tr', rejected) }
        .to raise_error(described_class::MissingLocalIdError)
      expect(rejected.calls).to eq(1)
    end

    it 'raises for blank entry, announcement, and instrument local ids' do
      expect { described_class.entry_iri('tr', 'list', nil) }
        .to raise_error(described_class::MissingLocalIdError, /entry IRI/)
      expect { described_class.announcement_iri('cn', nil) }
        .to raise_error(described_class::MissingLocalIdError,
                        /announcement IRI/)
      expect { described_class.legal_instrument_iri('cn', ' ') }
        .to raise_error(described_class::MissingLocalIdError,
                        /legal_instrument IRI/)
    end

    it 'carries source, kind, and value on the error' do
      expect { described_class.entity_iri('jp', nil) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.source).to eq('jp')
          expect(error.kind).to eq('entity')
          expect(error.value).to be_nil
        end
    end

    it 'truncates oversized rejected ids in the message' do
      huge = '!' * 5000 # sanitizes to nothing, preview stays bounded

      expect { described_class.entity_iri('us', huge) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
          expect(error.value).to eq(huge)
        end
    end

    it 'summarizes container ids instead of inspecting every element' do
      # Inspecting the whole container would build a ~500 KB string
      # just to report the error
      bulky = ['!'] * 100_000

      expect { described_class.entity_iri('us', bulky) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message).to include('Array(100000 entries)')
          expect(error.message.length).to be < 300
        end
    end

    it 'never inspects an unknown object type' do
      # #to_s is legitimately called to sanitize the id; #inspect is
      # purely diagnostic and could return anything, so it must not run
      hostile = Class.new do
        def to_s
          '!' # sanitizes to nothing, so the id is rejected
        end

        def inspect
          raise 'inspect must not be called on an unknown object type'
        end
      end.new

      expect { described_class.entity_iri('us', hostile) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message).to include('instance')
          expect(error.message.length).to be < 300
        end
    end

    it 'never calls to_s on an unknown source object' do
      hostile_source = Class.new do
        def to_s
          raise 'to_s must not be called on an unknown source'
        end
      end.new

      expect { described_class.entity_iri(hostile_source, nil) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
        end
    end

    it 'reports variable-length id types by class, not by value' do
      # A symbol's representation is unbounded, so it is never rendered
      huge_symbol = ('!' * 200_000).to_sym

      expect { described_class.entity_iri('us', huge_symbol) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message).to include('Symbol instance')
          expect(error.message.length).to be < 300
        end
    end

    it 'still raises MissingLocalIdError when the id itself misbehaves' do
      # Singleton overrides can defeat any dispatch rule, so the message
      # builder degrades rather than letting a foreign exception escape
      hostile = []
      def hostile.size
        raise 'size must not escape'
      end

      def hostile.to_s
        '!' # sanitizes to nothing, so the id is rejected
      end

      expect { described_class.entity_iri('us', hostile) }
        .to raise_error(described_class::MissingLocalIdError,
                        /\(unprintable\)/)
    end

    it 'never calls size on a container subclass' do
      # An overridden #size must not escape as an arbitrary exception
      # in place of MissingLocalIdError
      hostile = Class.new(Array) do
        def to_s
          '!' # sanitizes to nothing, so the id is rejected
        end

        def size
          raise 'size must not be called on a container subclass'
        end
      end.new

      expect { described_class.entity_iri('us', hostile) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
        end
    end

    it 'never inspects a subclass that could override inspect' do
      hostile = Class.new(Numeric) do
        def to_s
          '!' # sanitizes to nothing, so the id is rejected
        end

        def inspect
          raise 'inspect must not be called on a subclass'
        end
      end.new

      expect { described_class.entity_iri('us', hostile) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
        end
    end

    it 'still renders fixed-size id types by value' do
      expect { described_class.entity_iri('us', nil) }
        .to raise_error(described_class::MissingLocalIdError, /\bnil\b/)
    end

    it 'bounds an oversized source in the message' do
      expect { described_class.entity_iri('x' * 100_000, nil) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
        end
    end

    it 'keeps the preview bounded when escapes expand under inspect' do
      # Control characters inspect to 4 chars each ("\x01"); the cap
      # must apply to the inspected form, not just the raw slice
      noisy = "\x01" * 5000

      expect { described_class.entity_iri('us', noisy) }
        .to raise_error(described_class::MissingLocalIdError) do |error|
          expect(error.message.length).to be < 300
        end
    end

    it 'still accepts a literal "unknown" id string' do
      expect(described_class.entity_iri('cn', 'unknown'))
        .to eq('https://www.ammitto.org/entity/cn/unknown')
    end
  end

  describe '.entity_iri' do
    it 'generates LIST-AGNOSTIC entity IRI (no list_type)' do
      iri = described_class.entity_iri('cn', 'mitsubishi-heavy-industries')
      expect(iri).to eq('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')
    end

    it 'sanitizes components' do
      iri = described_class.entity_iri('CN', 'Mitsubishi Heavy Industries')
      expect(iri).to eq('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')
    end

    it 'generates same IRI for entity regardless of list' do
      # Entity IRIs are list-agnostic - same entity, same IRI
      iri1 = described_class.entity_iri('cn', 'mitsubishi-heavy-industries')
      iri2 = described_class.entity_iri('cn', 'mitsubishi-heavy-industries')
      expect(iri1).to eq(iri2)
    end
  end

  describe '.entry_iri' do
    it 'generates LIST-SPECIFIC entry IRI' do
      iri = described_class.entry_iri('cn', 'import-export-control-list', 'mitsubishi-heavy-industries')
      expect(iri).to eq('https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries')
    end

    it 'allows same entity to have different entries on different lists' do
      # Same entity, different list = different entry IRI
      iri1 = described_class.entry_iri('cn', 'import-export-control-list', 'mitsubishi-heavy-industries')
      iri2 = described_class.entry_iri('cn', 'unreliable-entity-list', 'mitsubishi-heavy-industries')

      expect(iri1).to include('import-export-control-list')
      expect(iri2).to include('unreliable-entity-list')
      expect(iri1).not_to eq(iri2)
    end

    it 'handles Russian stop-list' do
      iri = described_class.entry_iri('ru', 'stop-list', 'vladimir-putin')
      expect(iri).to eq('https://www.ammitto.org/entry/ru/stop-list/vladimir-putin')
    end

    it 'handles UK consolidated-list' do
      iri = described_class.entry_iri('uk', 'consolidated-list', 'some-entity')
      expect(iri).to eq('https://www.ammitto.org/entry/uk/consolidated-list/some-entity')
    end
  end

  describe '.announcement_iri' do
    it 'generates LIST-AGNOSTIC announcement IRI (no list_type)' do
      iri = described_class.announcement_iri('cn', 'mofcom-2026-11')
      expect(iri).to eq('https://www.ammitto.org/announcement/cn/mofcom-2026-11')
    end
  end

  describe '.legal_instrument_iri' do
    it 'generates LIST-AGNOSTIC legal instrument IRI (no list_type)' do
      iri = described_class.legal_instrument_iri('cn', 'export-control-law')
      expect(iri).to eq('https://www.ammitto.org/legal_instrument/cn/export-control-law')
    end
  end

  describe '.authority_iri' do
    it 'generates correct authority IRI' do
      iri = described_class.authority_iri('cn')
      expect(iri).to eq('https://www.ammitto.org/authority/cn')
    end

    it 'sanitizes the code' do
      iri = described_class.authority_iri('MOFCOM')
      expect(iri).to eq('https://www.ammitto.org/authority/mofcom')
    end
  end

  describe '.source_iri' do
    it 'generates correct source IRI' do
      iri = described_class.source_iri('cn')
      expect(iri).to eq('https://www.ammitto.org/source/cn')
    end
  end

  describe '.list_type_iri' do
    it 'generates correct list type IRI' do
      iri = described_class.list_type_iri('cn', 'import-export-control-list')
      expect(iri).to eq('https://www.ammitto.org/list/cn/import-export-control-list')
    end
  end

  describe '.parse_entity_iri' do
    it 'parses a valid entity IRI' do
      result = described_class.parse_entity_iri('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')
      expect(result).to eq({
                             type: 'entity',
                             source: 'cn',
                             local_id: 'mitsubishi-heavy-industries'
                           })
    end

    it 'returns nil for entry IRI' do
      expect(described_class.parse_entity_iri('https://www.ammitto.org/entry/cn/list/id')).to be_nil
    end
  end

  describe '.parse_entry_iri' do
    it 'parses a valid entry IRI' do
      result = described_class.parse_entry_iri('https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries')
      expect(result).to eq({
                             type: 'entry',
                             source: 'cn',
                             list_type: 'import-export-control-list',
                             local_id: 'mitsubishi-heavy-industries'
                           })
    end
  end

  describe '.parse_iri' do
    it 'parses entity IRI (list-agnostic)' do
      result = described_class.parse_iri('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')
      expect(result[:type]).to eq('entity')
      expect(result[:source]).to eq('cn')
      expect(result[:local_id]).to eq('mitsubishi-heavy-industries')
      expect(result).not_to have_key(:list_type)
    end

    it 'parses entry IRI (list-specific)' do
      result = described_class.parse_iri('https://www.ammitto.org/entry/cn/anti-sanction-list/marco-rubio')
      expect(result[:type]).to eq('entry')
      expect(result[:source]).to eq('cn')
      expect(result[:list_type]).to eq('anti-sanction-list')
      expect(result[:local_id]).to eq('marco-rubio')
    end

    it 'parses announcement IRI' do
      result = described_class.parse_iri('https://www.ammitto.org/announcement/cn/mofcom-2026-11')
      expect(result[:type]).to eq('announcement')
      expect(result[:source]).to eq('cn')
    end

    it 'parses legal instrument IRI' do
      result = described_class.parse_iri('https://www.ammitto.org/legal_instrument/cn/export-control-law')
      expect(result[:type]).to eq('legal_instrument')
      expect(result[:source]).to eq('cn')
    end

    it 'parses list type IRI' do
      result = described_class.parse_iri('https://www.ammitto.org/list/cn/import-export-control-list')
      expect(result[:type]).to eq('list')
      expect(result[:source]).to eq('cn')
      expect(result[:list_type]).to eq('import-export-control-list')
    end

    it 'returns nil for nil input' do
      expect(described_class.parse_iri(nil)).to be_nil
    end

    it 'returns nil for invalid base URI' do
      expect(described_class.parse_iri('https://example.com/entity/cn/list/id')).to be_nil
    end
  end

  describe '.valid_iri?' do
    it 'returns true for valid entity IRI' do
      expect(described_class.valid_iri?('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')).to be true
    end

    it 'returns true for valid entry IRI' do
      expect(described_class.valid_iri?('https://www.ammitto.org/entry/cn/list/id')).to be true
    end

    it 'returns false for invalid IRI' do
      expect(described_class.valid_iri?('https://example.com/entity/cn/list/id')).to be false
    end

    it 'returns false for nil' do
      expect(described_class.valid_iri?(nil)).to be false
    end
  end

  describe '.entity_iri_from_entry' do
    it 'extracts entity IRI from entry IRI' do
      entry_iri = 'https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries'
      entity_iri = described_class.entity_iri_from_entry(entry_iri)
      expect(entity_iri).to eq('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')
    end

    it 'returns nil for non-entry IRI' do
      expect(described_class.entity_iri_from_entry('https://www.ammitto.org/entity/cn/id')).to be_nil
    end
  end

  describe 'normalized knowledge graph structure' do
    it 'demonstrates same entity with different list entries' do
      entity = described_class.entity_iri('cn', 'mitsubishi-heavy-industries')
      entry1 = described_class.entry_iri('cn', 'import-export-control-list', 'mitsubishi-heavy-industries')
      entry2 = described_class.entry_iri('cn', 'unreliable-entity-list', 'mitsubishi-heavy-industries')

      # Entity IRI is list-agnostic
      expect(entity).to eq('https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries')

      # Entry IRIs are list-specific
      expect(entry1).to eq('https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries')
      expect(entry2).to eq('https://www.ammitto.org/entry/cn/unreliable-entity-list/mitsubishi-heavy-industries')

      # Can navigate from entry to entity
      expect(described_class.entity_iri_from_entry(entry1)).to eq(entity)
      expect(described_class.entity_iri_from_entry(entry2)).to eq(entity)
    end

    it 'demonstrates announcement is list-agnostic' do
      announcement = described_class.announcement_iri('cn', 'mofcom-2026-11')
      expect(announcement).to eq('https://www.ammitto.org/announcement/cn/mofcom-2026-11')
      expect(announcement).not_to include('list')
    end

    it 'demonstrates legal instrument is list-agnostic' do
      instrument = described_class.legal_instrument_iri('cn', 'export-control-law')
      expect(instrument).to eq('https://www.ammitto.org/legal_instrument/cn/export-control-law')
      expect(instrument).not_to include('list')
    end
  end
end
