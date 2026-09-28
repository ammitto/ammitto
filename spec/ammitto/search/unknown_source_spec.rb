# frozen_string_literal: true

require 'ammitto'

# An unknown source code used to be dropped before the search ran, so the
# result was empty and complete, indistinguishable from a clean negative.
RSpec.describe 'search with an unknown source code' do
  before { allow(Ammitto::Logger).to receive(:warn) }

  it 'reports the unknown code as skipped and the result as incomplete' do
    results = Ammitto.search('x', sources: [:zz])

    expect(results.skipped_sources).to eq([:zz])
    expect(results).not_to be_complete
  end

  it 'still searches the known codes alongside it' do
    allow(Faraday).to receive(:get)
      .and_raise(Faraday::ConnectionFailed.new('offline in specs'))
    known = instance_double(Ammitto::BaseSource,
                            load_data: { '@graph' => [] }, search: [])
    allow(Ammitto::Registry).to receive(:instance).and_call_original
    allow(Ammitto::Registry).to receive(:instance).with(:eu).and_return(known)

    results = Ammitto.search('x', sources: %i[zz eu])

    expect(results.skipped_sources).to eq([:zz])
    expect(known).to have_received(:load_data)
  end

  it 'reports the unknown code even for a blank term' do
    query = Ammitto::Search::QueryBuilder.new('', sources: [:zz])

    expect(query.execute).to eq([])
    expect(query.skipped_sources).to eq([:zz])
  end

  it 'lists skipped sources in the order they were requested' do
    dead = instance_double(Ammitto::BaseSource)
    allow(dead).to receive(:load_data)
      .and_raise(Ammitto::NetworkError.new('Failed to download ca data'))
    allow(Ammitto::Registry).to receive(:instance).and_call_original
    allow(Ammitto::Registry).to receive(:instance).with(:ca).and_return(dead)

    results = Ammitto.search('x', sources: %i[ca zz])

    expect(results.skipped_sources).to eq(%i[ca zz])
  end
end
