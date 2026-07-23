# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::ContactInfo do
  describe '#present?' do
    it 'requires at least one non-blank field' do
      expect(described_class.new(email: 'a@b.example')).to be_present
      expect(described_class.new(phone: '+41 31 000 00 00')).to be_present
      expect(described_class.new(website: 'https://x.example')).to be_present
      expect(described_class.new(fax: '123')).to be_present
    end

    it 'is blank when empty or whitespace-only' do
      expect(described_class.new).not_to be_present
      expect(described_class.new(email: '  ', phone: '')).not_to be_present
    end
  end
end
