# frozen_string_literal: true

# Records copied unchanged from the World Bank SANCTIONED_FIRM API
# (SUPP_ID 407985, 939357, 666304, 573628, 311048), parsed into
# SanctionedFirm objects keyed by SUPP_ID.
RSpec.shared_context 'with World Bank fixture firms' do
  let(:fixture) { File.read(File.expand_path('../fixtures/wb/sanctioned_firms_excerpt.json', __dir__)) }
  let(:firms) { Ammitto::Sources::Wb::Response.from_json(fixture).firms.to_h { |f| [f.supp_id, f] } }
end
