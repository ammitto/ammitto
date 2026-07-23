# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/config/override_resolver'

RSpec.describe Ammitto::Config::OverrideResolver do
  # Run a block with an ENV variable set (or removed when value is
  # nil), restoring the original value afterwards.
  def with_env(key, value)
    original = ENV.fetch(key, nil)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  # Pin both the primary variable and its alias for a block
  def with_sources_env(primary, alias_value, &block)
    with_env('AMMITTO_SOURCES_DIR', primary) do
      with_env('AMMITTO_DATA_DIR', alias_value, &block)
    end
  end

  describe ':sources_dir resolution' do
    it 'falls back to Defaults::SOURCES_DIR' do
      with_sources_env(nil, nil) do
        expect(described_class.new.resolve(:sources_dir))
          .to eq(Ammitto::Config::Defaults::SOURCES_DIR)
      end
    end

    it 'uses programmatic config over the default' do
      with_sources_env(nil, nil) do
        resolver = described_class.new(sources_dir: '/programmatic')
        expect(resolver.resolve(:sources_dir)).to eq('/programmatic')
      end
    end

    it 'prefers AMMITTO_SOURCES_DIR over programmatic config' do
      with_sources_env('/from-env', nil) do
        resolver = described_class.new(sources_dir: '/programmatic')
        expect(resolver.resolve(:sources_dir)).to eq('/from-env')
      end
    end

    it 'honors AMMITTO_DATA_DIR as an alias when the primary is unset' do
      with_sources_env(nil, '/from-alias') do
        expect(described_class.new.resolve(:sources_dir))
          .to eq('/from-alias')
      end
    end

    it 'prefers the primary variable over the alias' do
      with_sources_env('/primary', '/from-alias') do
        expect(described_class.new.resolve(:sources_dir)).to eq('/primary')
      end
    end

    it 'prefers a directly provided value over ENV' do
      with_sources_env('/from-env', nil) do
        expect(described_class.new.resolve(:sources_dir, provided: '/given'))
          .to eq('/given')
      end
    end

    it 'is included in resolve_all' do
      with_sources_env('/from-env', nil) do
        expect(described_class.new.resolve_all[:sources_dir])
          .to eq('/from-env')
      end
    end
  end

  describe ':cache_dir resolution (existing pattern)' do
    it 'falls back to Defaults::CACHE_DIR' do
      with_env('AMMITTO_CACHE_DIR', nil) do
        expect(described_class.new.resolve(:cache_dir))
          .to eq(Ammitto::Config::Defaults::CACHE_DIR)
      end
    end

    it 'prefers AMMITTO_CACHE_DIR over programmatic config' do
      with_env('AMMITTO_CACHE_DIR', '/env-cache') do
        resolver = described_class.new(cache_dir: '/programmatic')
        expect(resolver.resolve(:cache_dir)).to eq('/env-cache')
      end
    end
  end

  describe 'EnvProvider mapping' do
    it 'maps AMMITTO_SOURCES_DIR to :sources_dir' do
      with_sources_env('/from-env', nil) do
        config = Ammitto::Config::EnvProvider.configuration
        expect(config[:sources_dir]).to eq('/from-env')
      end
    end

    it 'maps the AMMITTO_DATA_DIR alias to :sources_dir' do
      with_sources_env(nil, '/from-alias') do
        config = Ammitto::Config::EnvProvider.configuration
        expect(config[:sources_dir]).to eq('/from-alias')
      end
    end

    it 'ignores empty values for both variable names' do
      with_sources_env('', '') do
        config = Ammitto::Config::EnvProvider.configuration
        expect(config).not_to have_key(:sources_dir)
      end
    end

    it 'counts the alias in any_set?' do
      with_sources_env(nil, '/from-alias') do
        expect(Ammitto::Config::EnvProvider.any_set?).to be(true)
      end
    end
  end
end
