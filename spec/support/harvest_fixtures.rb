# frozen_string_literal: true

# Helpers for driving FetchCommand's writer without a network call.
#
# Lives here rather than inside a `describe` so more than one spec can
# reach it; `spec_helper` already globs `spec/support/**/*.rb`.
module HarvestFixtures
  # A record the UK filename rule can name, and nothing more.
  #
  # `filename_for_item(:uk, item)` reads `unique_id`, so that is the only
  # thing these need to carry. `to_yaml` comes free from Struct.
  UkRecord = Struct.new(:unique_id)

  # @param count [Integer] how many records to build
  # @return [Array<UkRecord>] records with distinct identifiers
  def uk_records(count)
    Array.new(count) { |i| UkRecord.new("GBR#{i}") }
  end

  # Write the index a previous harvest would have left behind.
  #
  # @param dir [String] the output directory
  # @param count [Integer] what that harvest recorded
  # @return [void]
  def previous_harvest(dir, count)
    File.write(
      File.join(dir, '_index.yaml'),
      { 'source' => 'uk', 'count' => count,
        'fetched_at' => '2026-08-27T06:00:00Z',
        'schema' => 'ammitto:sources:uk:v1' }.to_yaml
    )
  end

  # Options shaped the way Thor hands them to a command.
  #
  # Thor passes `HashWithIndifferentAccess` with string keys, and the
  # command reads them with symbols. A plain Hash with either key style
  # would pass or fail for reasons the production path does not share, so
  # the examples build the real thing.
  #
  # @param overrides [Hash] option names to values
  # @return [Thor::CoreExt::HashWithIndifferentAccess] Thor-shaped options
  def thor_options(**overrides)
    Thor::CoreExt::HashWithIndifferentAccess.new(
      overrides.transform_keys(&:to_s)
    )
  end

  # Drive FetchCommand's writer directly.
  #
  # `write_items` is private, and it is the unit under test: it is where
  # the grouping, the collision check and the collapse check all happen,
  # and reaching it through `run` would need a network call and a parser.
  #
  # @param command [Ammitto::Cmd::FetchCommand] the command under test
  # @param records [Array] records to write
  # @param dir [String] output directory
  # @return [Hash] the claims the writer built
  def write_harvest(command, records, dir)
    command.send(:write_items, :uk, records, dir)
  end

  # Run a harvest that is expected to refuse, and hand back the error.
  #
  # @param command [Ammitto::Cmd::FetchCommand] the command under test
  # @param records [Array] records to write
  # @param dir [String] output directory
  # @return [StandardError, nil] the refusal, or nil if none was raised
  def refused_harvest(command, records, dir)
    write_harvest(command, records, dir)
    nil
  rescue Ammitto::Error => e
    e
  end

  # Files a run left in `dir`, excluding the index it writes itself.
  #
  # @param dir [String] the output directory
  # @return [Array<String>] record filenames
  def written_records(dir)
    Dir.children(dir).reject { |name| name.start_with?('_') }
  end
end
