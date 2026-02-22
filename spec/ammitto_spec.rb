# frozen_string_literal: true

RSpec.describe Ammitto do
  it 'has a version number' do
    expect(Ammitto::VERSION).not_to be nil
    expect(Ammitto::VERSION).to eq('1.0.0')
  end

  describe '.configure' do
    after { Ammitto.reset_configuration! }

    it 'allows configuration via block' do
      Ammitto.configure do |config|
        config.cache_ttl = 7200
        config.verbose = true
      end

      expect(Ammitto.configuration.cache_ttl).to eq(7200)
      expect(Ammitto.configuration.verbose).to be true
    end
  end

  describe '.sources' do
    it 'returns list of available source codes' do
      expect(Ammitto.sources).to be_an(Array)
      expect(Ammitto.sources).to include(:eu, :un, :us, :wb)
    end
  end

  describe '.schema' do
    it 'returns the schema context' do
      expect(Ammitto.schema).to respond_to(:context_url)
      expect(Ammitto.schema.context_url).to eq('https://ammitto.org/schema/v1/context.jsonld')
    end
  end

  describe 'error hierarchy' do
    it 'defines base error class' do
      expect(Ammitto::Error).to be < StandardError
    end

    it 'defines network error' do
      expect(Ammitto::NetworkError).to be < Ammitto::Error
    end

    it 'defines cache error' do
      expect(Ammitto::CacheError).to be < Ammitto::Error
    end

    it 'defines validation error' do
      expect(Ammitto::ValidationError).to be < Ammitto::Error
    end
  end
end
