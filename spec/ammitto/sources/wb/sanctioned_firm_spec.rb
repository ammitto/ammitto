# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/wb/sanctioned_firm'

RSpec.describe Ammitto::Sources::Wb::SanctionedFirm do
  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the presence check belongs on the class that
  # implements it.
  describe '#identifier' do
    it 'is supp_id when present' do
      expect(described_class.new(supp_id: 777).identifier).to eq(777)
    end

    it 'is nil when supp_id is blank' do
      expect(described_class.new(supp_id: nil).identifier).to be_nil
    end
  end

  describe 'parsing the API response' do
    include_context 'with World Bank fixture firms'

    it 'reads the register and creation fields' do
      firm = firms[407_985]
      expect(firm).to have_attributes(
        register_id: '0102133351', register: nil, parent: 'N', rechk_ind: 'N',
        create_user: '9000060495', create_user_name: 'Ho Quang Phuc',
        create_date: '2021-08-03T00:00:00.000Z', create_time: '1900-01-01T01:06:44.000Z'
      )
    end

    it 'reads the flag values the source carries' do
      expect(firms[939_357].register).to eq('Y')
      expect(firms[573_628].parent).to eq('Y')
      expect(firms[311_048].aml_entr_ind).to eq('S')
    end

    it 'keeps the new fields through the processed YAML round trip' do
      restored = described_class.from_yaml(firms[407_985].to_yaml)
      expect(restored).to have_attributes(register_id: '0102133351', create_date: '2021-08-03T00:00:00.000Z')
    end

    it 'does not keep the export stamps the API puts on every record' do
      expect(firms[407_985].to_yaml).not_to match(/upd_|last_refresh/)
    end
  end
end
