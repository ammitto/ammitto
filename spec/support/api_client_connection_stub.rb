# frozen_string_literal: true

# BaseSource downloads through ApiClient's connection, so a spec that
# needs a canned response or an unreachable host stubs that connection
# rather than Faraday's module-level get. Shared by the API host and
# network failure specs.
module ApiClientConnectionStub
  # @return [RSpec::Mocks::MessageExpectation] to chain the response onto
  def stub_api_client_get
    client = Ammitto::Client::ApiClient.new
    allow(Ammitto::Client::ApiClient).to receive(:new).and_return(client)
    allow(client.connection).to receive(:get)
  end
end
