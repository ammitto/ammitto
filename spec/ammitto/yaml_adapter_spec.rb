# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'lutaml-model adapter selection' do
  # yeptris is always present in the bundle (a hard transitive dependency
  # via canon), and its Linux FFI fallback is unsafe (see lib/ammitto.rb).
  # `require 'ammitto'` (via spec_helper) must have already forced both
  # formats onto the standard adapter, before this or any other example
  # runs.
  it 'resolves :yaml to the standard adapter, not yeptris' do
    expect(Lutaml::Model::AdapterResolver.adapter_for(:yaml))
      .to eq(Lutaml::KeyValue::Adapter::Yaml::StandardAdapter)
  end

  it 'resolves :json to the standard adapter, not yeptris' do
    expect(Lutaml::Model::AdapterResolver.adapter_for(:json))
      .to eq(Lutaml::KeyValue::Adapter::Json::StandardAdapter)
  end
end
