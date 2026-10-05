# frozen_string_literal: true

require 'ammitto'

RSpec.describe 'Ammitto.search term' do
  # The term the query searched, not the caller's spelling of it.
  it 'is the term the query actually searched' do
    query = Ammitto::Search::QueryBuilder.new('  kim  ')
    allow(query).to receive(:execute).and_return([])
    allow(Ammitto::Search::QueryBuilder).to receive(:new).and_return(query)

    expect(Ammitto.search('  kim  ').term).to eq('kim')
  end
end
