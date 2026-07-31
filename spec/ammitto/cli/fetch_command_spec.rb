# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

RSpec.describe Ammitto::Cmd::FetchCommand do
  it 'reports CN as manually managed instead of a silent extractor success' do
    cmd = described_class.new({}, ['cn'])
    result = cmd.send(:fetch_source, :cn)

    expect(result[:status]).to eq(:error)
    expect(result[:error]).to match(/manually managed in data-cn/)
  end

  it 'requires sources or --all' do
    expect { described_class.new({}, []) }
      .to raise_error(Thor::Error, /No sources specified/)
  end

  it 'excludes cn from --all so full runs can succeed' do
    cmd = described_class.new({ all: true }, [])

    expect(cmd.sources).not_to include(:cn)
    expect(cmd.sources)
      .to match_array(Ammitto::Config::Defaults::ALL_SOURCES - %i[cn])
  end

  describe 'exit honesty' do
    it 'raises Thor::Error when a requested source fails' do
      cmd = described_class.new({}, ['cn'])

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: cn/)
        .and output(/0 succeeded, 1 failed/).to_stdout
    end

    it 'fails the run when only some sources fail' do
      cmd = described_class.new({}, %w[uk cn])
      allow(cmd).to receive(:fetch_source).and_call_original
      allow(cmd).to receive(:fetch_source)
        .with(:uk).and_return({ code: :uk, status: :success, count: 3 })

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: cn/)
        .and output(/1 succeeded, 1 failed/).to_stdout
    end

    it 'names every failed source in the error' do
      cmd = described_class.new({}, %w[uk eu])
      allow(cmd).to receive(:fetch_source) do |source|
        { code: source, status: :error, error: 'boom' }
      end

      expect { cmd.run }
        .to raise_error(Thor::Error, /Fetch failed for: uk, eu/)
        .and output(/0 succeeded, 2 failed/).to_stdout
    end

    it 'does not raise when all requested sources succeed' do
      cmd = described_class.new({}, %w[uk])
      allow(cmd).to receive(:fetch_source)
        .with(:uk).and_return({ code: :uk, status: :success, count: 3 })

      expect { cmd.run }
        .to output(/1 succeeded, 0 failed/).to_stdout
    end
  end
end
