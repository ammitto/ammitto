# frozen_string_literal: true

RSpec.describe Ammitto do

  before :each do
    allow(Ammitto::Processor).to receive(:prepare).and_return(nil)
    stubbed_files = ["spec/examples/eu-data/ammach-hud-34.yaml",
                     "spec/examples/eu-data/salih-al-7.yaml",
                     "spec/examples/un-data/aziz-salih-136.yaml",
                     "spec/examples/us-govt-data/ali-salim-26.yaml",
                     "spec/examples/wb-data/services-sa-259.yaml",
    ]
    allow(Dir).to receive(:[]).and_return(stubbed_files)
    stub_const("Ammitto::Processor::DATA_SOURCES", ['un-data','us-govt-data','eu-data','wb-data'])
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
      expect(result.length).to be 16
      expect(result.map{|item| item.names.join(" ").include?('Salih')}.uniq.first).to be true
    end

    it "searches a name with street address from all data sources and find expected results" do
      result = Ammitto::search('AZIZ SALIH AL-NUMAN', {addresses: {street: 'house 28'}})
      expect(result.empty?).to be false
      expect(result.length).to be 4
    end

    it "searches a name with ref number from all data sources and find expected results" do
      result = Ammitto::search('AZIZ SALIH AL-NUMAN', {ref_number: 'IQi.008'})
      expect(result.empty?).to be false
      expect(result.length).to be 4
    end

  end


end


