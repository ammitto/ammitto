# frozen_string_literal: true

# Entries copied unchanged from OFAC's sdn.xml (uids 7006, 4243, 6946,
# 6924, 4238): nationality, citizenship and vessel details.
RSpec.shared_context 'with OFAC SDN excerpt' do
  let(:fixture) { File.read(File.expand_path('../fixtures/us/sdn_excerpt.xml', __dir__)) }
end
