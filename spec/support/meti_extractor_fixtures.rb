# frozen_string_literal: true

# Doubles for the METI Foreign User List path.
#
# Lives here rather than inside a `describe` so the CLI spec and any later
# extractor spec share one definition; `spec_helper` already globs
# `spec/support/**/*.rb`. The constants are resolved inside the methods, not
# at load time, because this file is required before `ammitto` itself.
module MetiExtractorFixtures
  # A parsed list reporting `count` entities.
  #
  # @param count [Integer] entities the parse produced
  # @return [RSpec::Mocks::InstanceVerifyingDouble] a ForeignUserList double
  def meti_list(count)
    instance_double(
      Ammitto::Data::Japan::Meti::ForeignUserList,
      count: count,
      to_hash: {
        'source_url' => 'https://www.meti.go.jp/policy/anpo/law00.html',
        'entities' => Array.new(count) { |i| { 'id' => "jp-meti-#{i}" } }
      }
    )
  end

  # Make `Meti::Extractor.new` return an extractor whose `fetch` yields
  # `list`, so the constructor keywords stay inspectable.
  #
  # @param list [RSpec::Mocks::InstanceVerifyingDouble] what `fetch` returns
  # @return [RSpec::Mocks::InstanceVerifyingDouble] the extractor double
  def stub_meti_extractor(list)
    extractor = instance_double(
      Ammitto::Data::Japan::Meti::Extractor, fetch: list
    )
    allow(Ammitto::Data::Japan::Meti::Extractor)
      .to receive(:new).and_return(extractor)
    extractor
  end

  # Stub the extractor and hand back a holder for the `output_dir:` it was
  # constructed with, so an example can assert what happened to that
  # directory after the command returned rather than only that an argument
  # was forwarded.
  #
  # @param count [Integer] entities the stubbed parse reports
  # @return [Struct] responds to `value`, the captured `output_dir`
  def capture_meti_download_dir(count = 1)
    holder = Struct.new(:value).new(nil)
    extractor = instance_double(
      Ammitto::Data::Japan::Meti::Extractor, fetch: meti_list(count)
    )
    allow(Ammitto::Data::Japan::Meti::Extractor)
      .to receive(:new) do |output_dir:, verbose:| # rubocop:disable Lint/UnusedBlockArgument
        holder.value = output_dir
        extractor
      end
    holder
  end
end
