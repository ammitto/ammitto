# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ru::Entity do
  it 'is a person and not an organization when the type is individual' do
    entity = described_class.new(type: 'individual')

    expect([entity.person?, entity.organization?]).to eq([true, false])
  end

  it 'is an organization and not a person when the type is organization' do
    entity = described_class.new(type: 'organization')

    expect([entity.organization?, entity.person?]).to eq([true, false])
  end

  [nil, 'person'].each do |type|
    it "is neither a person nor an organization when the type is #{type.inspect}" do
      entity = described_class.new(type: type)

      expect([entity.person?, entity.organization?]).to eq([false, false])
    end
  end
end
