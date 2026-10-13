# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un/individual'

RSpec.describe Ammitto::Sources::Un::Individual do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is reference_number when present' do
      expect(described_class.new(reference_number: 'QDi.001').identifier)
        .to eq('QDi.001')
    end

    it 'drops a trailing space from the reference number' do
      expect(described_class.new(reference_number: 'QDi.001 ').identifier)
        .to eq('QDi.001')
    end

    it 'is nil when reference_number is blank' do
      expect(described_class.new(reference_number: nil).identifier).to be_nil
    end
  end

  # CDi.011 as published in the consolidated list on 2026-10-13: two dates
  # and three places of birth, and a <VALUE>-wrapped LIST_TYPE.
  describe 'parsing a record with several births' do
    let(:xml) do
      <<~XML
        <INDIVIDUAL>
              <DATAID>6908002</DATAID>
              <VERSIONNUM>1</VERSIONNUM>
              <FIRST_NAME>IRUTA DOUGLAS</FIRST_NAME>
              <SECOND_NAME>MPAMO</SECOND_NAME>
              <UN_LIST_TYPE>DRC</UN_LIST_TYPE>
              <REFERENCE_NUMBER>CDi.011</REFERENCE_NUMBER>
              <LISTED_ON>2005-11-01</LISTED_ON>
              <GENDER>Male</GENDER>
              <HAS_INTERPOL_LINK>YES</HAS_INTERPOL_LINK>
              <INTERPOL_LINK>https://www.interpol.int/en/How-we-work/Notices/View-UN-Notices-Individuals#2013-16083</INTERPOL_LINK>
              <NATIONALITY>
                <VALUE>Democratic Republic of the Congo</VALUE>
              </NATIONALITY>
              <LIST_TYPE>
                <VALUE>UN List</VALUE>
              </LIST_TYPE>
              <LAST_DAY_UPDATED>
                <VALUE/>
              </LAST_DAY_UPDATED>
              <INDIVIDUAL_ALIAS>
                <QUALITY>Good</QUALITY>
                <ALIAS_NAME>Douglas Iruta Mpamo</ALIAS_NAME>
              </INDIVIDUAL_ALIAS>
              <INDIVIDUAL_ALIAS>
                <QUALITY>Low</QUALITY>
                <ALIAS_NAME>Mpano</ALIAS_NAME>
              </INDIVIDUAL_ALIAS>
              <INDIVIDUAL_ADDRESS>
                <CITY>Gisenyi</CITY>
                <COUNTRY>Rwanda</COUNTRY>
                <NOTE>As of June 2011.</NOTE>
              </INDIVIDUAL_ADDRESS>
              <INDIVIDUAL_DATE_OF_BIRTH>
                <TYPE_OF_DATE>EXACT</TYPE_OF_DATE>
                <DATE>1965-12-28</DATE>
              </INDIVIDUAL_DATE_OF_BIRTH>
              <INDIVIDUAL_DATE_OF_BIRTH>
                <TYPE_OF_DATE>EXACT</TYPE_OF_DATE>
                <DATE>1965-12-29</DATE>
              </INDIVIDUAL_DATE_OF_BIRTH>
              <INDIVIDUAL_PLACE_OF_BIRTH>
                <CITY>Bashali</CITY>
                <STATE_PROVINCE>Masisi</STATE_PROVINCE>
                <COUNTRY>Democratic Republic of the Congo</COUNTRY>
              </INDIVIDUAL_PLACE_OF_BIRTH>
              <INDIVIDUAL_PLACE_OF_BIRTH>
                <CITY>Goma</CITY>
                <COUNTRY>Democratic Republic of the Congo</COUNTRY>
              </INDIVIDUAL_PLACE_OF_BIRTH>
              <INDIVIDUAL_PLACE_OF_BIRTH>
                <CITY>Uvira</CITY>
                <COUNTRY>Democratic Republic of the Congo</COUNTRY>
              </INDIVIDUAL_PLACE_OF_BIRTH>
              <INDIVIDUAL_DOCUMENT/>
              <SORT_KEY/>
              <SORT_KEY_LAST_MOD/>
            </INDIVIDUAL>
      XML
    end
    let(:individual) { described_class.from_xml(xml) }

    it 'keeps every date of birth' do
      expect(individual.date_of_birth.map(&:date)).to eq(%w[1965-12-28 1965-12-29])
    end

    it 'keeps every place of birth' do
      expect(individual.place_of_birth.map(&:city)).to eq(%w[Bashali Goma Uvira])
    end

    it 'reads an empty LAST_DAY_UPDATED as no value, not as whitespace' do
      expect(individual.last_day_updated.value).to be_empty
    end

    it 'reads LIST_TYPE from the inner VALUE, not the surrounding whitespace' do
      expect(individual.list_type.value).to eq(['UN List'])
    end
  end
end
