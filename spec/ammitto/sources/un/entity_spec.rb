# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un/entity'

RSpec.describe Ammitto::Sources::Un::Entity do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is reference_number when present' do
      expect(described_class.new(reference_number: 'QDe.001').identifier)
        .to eq('QDe.001')
    end

    it 'is nil when reference_number is blank' do
      expect(described_class.new(reference_number: nil).identifier).to be_nil
    end
  end

  # KPe.023 as published in the consolidated list on 2026-10-13: the
  # reference number carries a trailing space.
  describe 'parsing a record whose reference number has a trailing space' do
    let(:entity) do
      described_class.from_xml(<<~XML)
        <ENTITY>
          <DATAID>6908499</DATAID>
          <VERSIONNUM>1</VERSIONNUM>
          <FIRST_NAME>DAEDONG CREDIT BANK (DCB)</FIRST_NAME>
          <UN_LIST_TYPE>DPRK</UN_LIST_TYPE>
          <REFERENCE_NUMBER>KPe.023 </REFERENCE_NUMBER>
          <LISTED_ON>2016-03-02</LISTED_ON>
          <LIST_TYPE>
            <VALUE>UN List</VALUE>
          </LIST_TYPE>
          <LAST_DAY_UPDATED>
            <VALUE>2022-07-26</VALUE>
          </LAST_DAY_UPDATED>
        </ENTITY>
      XML
    end

    it 'names the file after the reference number without the space' do
      expect(entity.identifier).to eq('KPe.023')
    end

    it 'reads LAST_DAY_UPDATED from the inner VALUE' do
      expect(entity.last_day_updated.value).to eq(['2022-07-26'])
    end
  end
end
