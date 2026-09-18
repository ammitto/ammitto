# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ammitto::Sources::Wb::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :wb' do
      expect(transformer.source_code).to eq(:wb)
    end
  end

  describe '#authority' do
    it 'returns WB authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('wb')
      expect(auth.name).to eq('World Bank')
    end
  end

  # debar_from_date/debar_to_date were discarded silently to nil before
  # this change, through the shared base_transformer#parse_date; the
  # published value must not change in any mode.
  describe 'parse failure visibility for debarment dates' do
    let(:io) { StringIO.new }
    let(:firm) do
      Ammitto::Sources::Wb::SanctionedFirm.new(
        supp_id: 1,
        supp_name: 'Example Firm',
        supp_type_code: 'O',
        debar_from_date: 'not-a-date',
        debar_to_date: '2099-01-01'
      )
    end

    before do
      Ammitto.reset_configuration!
      Ammitto::Logger.logger = Logger.new(io)
    end

    after do
      Ammitto::Logger.logger = nil
      ENV.delete('AMMITTO_PARSE_FAILURE_MODE')
    end

    it 'warns and counts once, publishing nil exactly as before' do
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = transformer.transform(firm)
      end

      expect(result[:entry].period.effective_date).to be_nil
      expect(io.string).to include('Parse failure in wb.debar_from_date')
      expect(run.count(:wb)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = transformer.transform(firm)
      end

      expect(result[:entry].period.effective_date).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:wb)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { transformer.send(:parse_wb_date, 'not-a-date', field: :debar_from_date) }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:wb)
          expect(e.field).to eq(:debar_from_date)
        }
    end
  end
end
