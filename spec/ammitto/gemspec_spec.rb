# frozen_string_literal: true

RSpec.describe 'ammitto.gemspec' do
  subject(:gemspec) do
    Gem::Specification.load(
      File.expand_path('../../ammitto.gemspec', __dir__)
    )
  end

  # data-ch and data-uk pin json-schema ~> 5.0; a gemspec pinned to ~> 4.0
  # made `bundle lock` unresolvable there (exit 6), freezing both fetch
  # pipelines. The constraint must admit both major versions 4 and 5.
  it 'allows json-schema 4 and 5 but not 6' do
    dep = gemspec.dependencies.find { |d| d.name == 'json-schema' }

    expect(dep).not_to be_nil
    expect(dep.requirement).to be_satisfied_by(Gem::Version.new('4.0.0'))
    expect(dep.requirement).to be_satisfied_by(Gem::Version.new('5.2.0'))
    expect(dep.requirement).not_to be_satisfied_by(Gem::Version.new('6.0.0'))
  end

  # UsExtractor requires 'zip' directly for the OFAC ZIP fallback. rubyzip
  # reached the gem only through roo and lutaml-model, so a consumer whose
  # resolution dropped it got a LoadError on the largest source's fallback
  # path -- and LoadError is not a StandardError, so no rescue in the gem
  # would have caught it.
  it 'declares rubyzip, which the OFAC ZIP fallback requires directly' do
    dep = gemspec.dependencies.find { |d| d.name == 'rubyzip' }

    expect(dep).not_to be_nil
    expect(dep.requirement).to be_satisfied_by(Gem::Version.new('2.4.1'))
  end
end
