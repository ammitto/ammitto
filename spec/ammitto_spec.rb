# frozen_string_literal: true

RSpec.describe Ammitto do

  around(:each) do |example|
    VCR.use_cassette("load_data", &example)
  end

  it "has a version number" do
    expect(Ammitto::VERSION).not_to be nil
  end

  context "search" do
    it "will always respond with SanctionItem collection object" do
      result = Ammitto::search('abcdef')
      expect(result).to be_instance_of Ammitto::SanctionItemCollection
      result = Ammitto::search('Salih')
      expect(result).to be_instance_of Ammitto::SanctionItemCollection
    end

    it "response collection will only have SanctionItem type object" do
      result = Ammitto::search('Salih')
      expect(result.map(&:class).uniq.first).to be Ammitto::SanctionItem
    end

    it "searches a name from all data sources and find expected results" do
      result = Ammitto::search('Salih')
      expect(result.empty?).to be false
      expect(result.length).to be 24
      expect(result.map{|item| item.names.join(" ").include?('Salih')}.uniq.first).to be true
    end

  end


end


