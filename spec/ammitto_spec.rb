# frozen_string_literal: true

RSpec.describe Ammitto do
  it "has a version number" do
    expect(Ammitto::VERSION).not_to be nil
  end

  it "searches a name 'Salih' from all data sources and find expected results" do
    expect(Ammitto::search('Salih').length).to be 24
  end
end
