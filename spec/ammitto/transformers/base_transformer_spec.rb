# frozen_string_literal: true

require 'spec_helper'

# Calls the private date helpers inside the example's parse failure run.
module BaseTransformerSpecHelpers
  def parse_counting(value, **kwargs)
    count_parse_failures { transformer.send(:parse_date, value, **kwargs) }
  end

  def period_counting(**kwargs)
    count_parse_failures { transformer.send(:create_period, source: :test, **kwargs) }
  end
end

RSpec.describe Ammitto::Transformers::BaseTransformer do
  include BaseTransformerSpecHelpers

  let(:transformer) { described_class.new(:test) }

  describe '#source_code' do
    it 'returns the source code' do
      expect(transformer.source_code).to eq(:test)
    end
  end

  describe '#transform' do
    it 'raises NotImplementedError' do
      expect { transformer.transform({}) }.to raise_error(NotImplementedError)
    end
  end

  describe '#generate_entity_id' do
    it 'generates a LIST-AGNOSTIC entity URI (sanitized to lowercase)' do
      id = transformer.send(:generate_entity_id, 'TEST123')
      # Entity IRIs are list-agnostic (no list_type) and sanitized to lowercase
      expect(id).to eq('https://www.ammitto.org/entity/test/test123')
    end
  end

  describe '#generate_entry_id' do
    it 'generates a LIST-SPECIFIC entry URI' do
      id = transformer.send(:generate_entry_id, 'TEST123')
      # Entry IRIs are list-specific and include list_type
      # For unknown source like :test, default_list_type returns nil which becomes 'unknown'
      expect(id).to eq('https://www.ammitto.org/entry/test/unknown/test123')
    end

    it 'allows list_type override' do
      id = transformer.send(:generate_entry_id, 'TEST123', entry_list_type: 'consolidated-list')
      expect(id).to eq('https://www.ammitto.org/entry/test/consolidated-list/test123')
    end
  end

  describe '#authority' do
    it 'returns the authority for the source' do
      auth = transformer.send(:authority)
      expect(auth).to be_nil # :test is not a registered authority
    end
  end

  describe '#parse_date' do
    include_context 'with parse failure log capture'

    it 'warns and counts an unreadable value when source and field are given' do
      expect(parse_counting('not-a-date', source: :test, field: :listed_date)).to be_nil
      expect(io.string).to include('Parse failure in test.listed_date')
      expect(run.count(:test)).to eq(1)
    end

    it 'reports a value longer than Date.parse accepts instead of raising' do
      # Past 128 characters Date.parse raises a plain ArgumentError, not
      # Date::Error, so a narrower rescue let the whole transform crash.
      long = '1' * 200

      expect(parse_counting(long, source: :test, field: :listed_date)).to be_nil
      expect(run.count(:test)).to eq(1)
    end

    it 'does not report without both source and field' do
      parse_counting('not-a-date')
      parse_counting('not-a-date', source: :test)
      parse_counting('not-a-date', field: :listed_date)

      expect(run.count(:test)).to eq(0)
      expect(io.string).to be_empty
    end

    it 'does not report an absent value' do
      expect(parse_counting(nil, source: :test, field: :listed_date)).to be_nil
      expect(parse_counting('', source: :test, field: :listed_date)).to be_nil

      expect(run.count(:test)).to eq(0)
    end

    it 'does not report a value that parses' do
      expect(parse_counting('2020-01-02', source: :test, field: :listed_date)).to eq(Date.new(2020, 1, 2))
      expect(run.count(:test)).to eq(0)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { transformer.send(:parse_date, 'not-a-date', source: :test, field: :listed_date) }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:test)
          expect(e.field).to eq(:listed_date)
          expect(e.value).to eq('not-a-date')
        }
    end
  end

  describe '#create_period' do
    include_context 'with parse failure log capture'

    it 'requires source' do
      expect { transformer.send(:create_period, listed_date: '2020-01-02') }
        .to raise_error(ArgumentError, /source/)
    end

    it 'reports each unreadable date under its own field name' do
      period = period_counting(listed_date: 'bad-listed', effective_date: 'bad-effective',
                               expiry_date: 'bad-expiry')

      expect([period.listed_date, period.effective_date, period.expiry_date]).to all(be_nil)
      expect(io.string).to include('Parse failure in test.listed_date')
        .and include('Parse failure in test.effective_date')
        .and include('Parse failure in test.expiry_date')
      expect(run.count(:test)).to eq(3)
    end

    it 'counts one failure when one value is both listed_date and effective_date' do
      period_counting(listed_date: 'not-a-date', effective_date: 'not-a-date')

      expect(run.count(:test)).to eq(1)
    end

    it 'publishes readable dates and Date objects unchanged, without reporting' do
      period = period_counting(listed_date: '2020-01-02', effective_date: Date.new(2020, 1, 3),
                               expiry_date: '2021-01-04')

      expect(period.listed_date).to eq(Date.new(2020, 1, 2))
      expect(period.effective_date).to eq(Date.new(2020, 1, 3))
      expect(period.expiry_date).to eq(Date.new(2021, 1, 4))
      expect(period.is_indefinite).to be(false)
      expect(run.count(:test)).to eq(0)
    end

    it 'marks a period with no stated expiry as indefinite' do
      expect([period_counting.is_indefinite, period_counting(expiry_date: '').is_indefinite])
        .to eq([true, true])
      expect(run.count(:test)).to eq(0)
    end

    # An expiry the source stated but this gem could not read neither
    # proves a scheduled end nor its absence.
    it 'leaves is_indefinite unasserted for an unreadable expiry and reports it' do
      period = period_counting(expiry_date: 'until further notice')

      expect(period.expiry_date).to be_nil
      expect(period.is_indefinite).to be_nil
      expect(io.string).to include('Parse failure in test.expiry_date')
      expect(run.count(:test)).to eq(1)
    end

    it 'omits isIndefinite from the JSON-LD period when it is unasserted' do
      period = period_counting(expiry_date: 'until further notice')

      expect(Ammitto::Serialization::JsonLdSerializer.new.send(:serialize_period, period))
        .not_to have_key('isIndefinite')
    end
  end
end
