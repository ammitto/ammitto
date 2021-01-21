# frozen_string_literal: true

require "yaml"

RSpec.describe "Ammitto" => :SanctionItem do
  context "instance" do
    subject do
      hash = YAML.load_file "spec/examples/sanction_item.yml"
      Ammitto::SanctionItem.new(hash)
    end

    it "is instance of SanctionItem" do
      expect(subject).to be_instance_of Ammitto::SanctionItem
    end

    it "has array of names" do
      expect(subject.names).to be_instance_of(Array)
      expect(subject.names.first).to eq("HAMID HAMAD HAMID AL-‘ALI")
    end

    it "has array of addresses" do
      expect(subject.addresses).to be_instance_of(Array)
      expect(subject.addresses.first).to be_instance_of Ammitto::Address
    end

    it "has array of documents" do
      expect(subject.addresses).to be_instance_of(Array)
      expect(subject.documents.first).to be_instance_of Ammitto::Document
    end

  end
end
