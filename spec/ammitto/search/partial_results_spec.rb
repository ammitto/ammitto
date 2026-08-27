# frozen_string_literal: true

require 'ammitto'

# A search that quietly returns fewer results than the corpus holds is the
# dangerous direction for a sanctions dataset.
#
# `QueryBuilder#execute` skips a source it cannot read so that one unreachable
# source does not take the whole search down. That skip is correct. But it used
# to be invisible: the caller received a smaller ResultSet with no way to tell
# it apart from "fewer matches exist", so a screening lookup could report no
# match while three sources had failed to load.
RSpec.describe 'a search that could not read every source' do
  let(:unreachable) do
    Class.new(Ammitto::BaseSource) do
      def code = :tr

      def load_data(*)
        raise Ammitto::NetworkError.new('Failed to download tr data', url: 'x')
      end
    end.new
  end

  let(:reachable) do
    Class.new(Ammitto::BaseSource) do
      def code = :eu

      def load_data(*) = { '@graph' => [] }

      def search(_term, _data) = [{ '@id' => 'eu-1', 'names' => [{ 'fullName' => 'Match' }] }]
    end.new
  end

  before do
    allow(Ammitto::Registry).to receive(:instance).with(:tr).and_return(unreachable)
    allow(Ammitto::Registry).to receive(:instance).with(:eu).and_return(reachable)
  end

  it 'still returns what it could read' do
    results = Ammitto.search('match', sources: %i[eu tr])

    expect(results.size).to eq(1)
  end

  it 'names the source it could not read' do
    results = Ammitto.search('match', sources: %i[eu tr])

    expect(results.skipped_sources).to eq([:tr])
  end

  it 'reports itself as incomplete' do
    results = Ammitto.search('match', sources: %i[eu tr])

    expect(results).not_to be_complete
  end

  it 'reports itself as complete when every source was read' do
    results = Ammitto.search('match', sources: [:eu])

    expect(results).to be_complete
    expect(results.skipped_sources).to be_empty
  end

  it 'keeps the warning when a slice is taken' do
    # Filtering must not launder a partial result into one that looks whole.
    results = Ammitto.search('match', sources: %i[eu tr]).by_entity_type('person')

    expect(results.skipped_sources).to eq([:tr])
    expect(results).not_to be_complete
  end

  it 'keeps the warning through the other two filters as well' do
    partial = Ammitto.search('match', sources: %i[eu tr])

    expect(partial.by_authority('any').skipped_sources).to eq([:tr])
    expect(partial.by_status('active').skipped_sources).to eq([:tr])
  end

  # `complete?` reads this list, so a caller who could empty it could turn
  # an inconclusive screening result into a clean negative.
  it 'refuses to let a caller empty the list' do
    results = Ammitto.search('match', sources: %i[eu tr])

    expect { results.skipped_sources.clear }.to raise_error(FrozenError)
    expect(results).not_to be_complete
  end

  it 'does not share the array it was handed' do
    handed = [:eu]
    results = Ammitto::Search::ResultSet.new([], skipped_sources: handed)
    handed << :us

    expect(results.skipped_sources).to eq([:eu])
  end

  # The registry is mutable and #instance may return nil. A code we cannot
  # instantiate is a source we did not read, which is exactly what this
  # list is for.
  it 'records a source it could not instantiate at all' do
    allow(Ammitto::Registry).to receive(:instance).and_call_original
    allow(Ammitto::Registry).to receive(:instance).with(:tr).and_return(nil)

    results = Ammitto.search('match', sources: %i[eu tr])

    expect(results.skipped_sources).to include(:tr)
    expect(results).not_to be_complete
  end
end
