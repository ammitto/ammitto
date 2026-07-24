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
end
