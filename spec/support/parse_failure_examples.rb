# frozen_string_literal: true

# Shared parse failure examples for source parsers. Both groups need the
# 'with parse failure log capture' context in the including group.
#
# 'a reported parse failure' expects these from the including group:
#   parse_unreadable     a lambda that parses an unreadable value and
#                        returns what the source publishes for it
#   raise_unreadable     a lambda that reports that failure, for raise mode
# and accepts, through the it_behaves_like block:
#   parse_unreadable_silently  the call for silent mode, when it differs
#   published_matcher          what is published, when it is not nil
RSpec.shared_examples 'a reported parse failure' do |source:, field:, raised_field: field, raised_value: nil|
  let(:parse_unreadable_silently) { parse_unreadable }
  let(:published_matcher) { be_nil }

  it 'warns and counts, still publishing the fallback value' do
    expect(count_parse_failures { parse_unreadable.call }).to(published_matcher)
    expect(io.string).to include("Parse failure in #{source}.#{field}")
    expect(run.count(source)).to eq(1)
  end

  it 'stays silent but still counts in silent mode' do
    Ammitto.configure { |config| config.parse_failure_mode = :silent }

    expect(count_parse_failures { parse_unreadable_silently.call }).to(published_matcher)
    expect(io.string).to be_empty
    expect(run.count(source)).to eq(1)
  end

  it 'raises Ammitto::ParseFailureError in raise mode' do
    Ammitto.configure { |config| config.parse_failure_mode = :raise }

    expect { raise_unreadable.call }
      .to raise_error(Ammitto::ParseFailureError) { |e|
        expect(e.source).to eq(source)
        expect(e.field).to eq(raised_field)
        expect(e.value).to eq(raised_value) if raised_value
      }
  end
end

# One unreadable source date that fills both listed_date and
# effective_date of the period is one failure, not two. The including
# group supplies entry_with_unreadable_date, a lambda returning the entry.
# field is the name reported; register_field the name the register uses.
RSpec.shared_examples 'a parse failure counted once across period dates' do |source:, field:, register_field:|
  it "counts an unreadable #{register_field} once although it fills two period dates" do
    entry = count_parse_failures { entry_with_unreadable_date.call }

    expect(entry.period.listed_date).to be_nil
    expect(entry.period.effective_date).to be_nil
    expect(io.string).to include("Parse failure in #{source}.#{field}")
    expect(run.count(source)).to eq(1)
  end
end
