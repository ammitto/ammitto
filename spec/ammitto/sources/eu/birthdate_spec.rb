# frozen_string_literal: true

require 'spec_helper'

# The EU states a span of birth years as two XML attributes rather than
# as text. The pipeline runs XML -> source model -> YAML (the fetch
# artifact) -> BirthInfo (harmonize), so each hop is checked: a bound
# that survives parsing but not the YAML artifact never reaches
# harmonize at all.
#
# The fixture attributes are copied verbatim from the live EU
# consolidated export, which carries 55 yearRangeFrom and 56
# yearRangeTo attributes.
RSpec.describe Ammitto::Sources::Eu::Birthdate do
  def parse(attributes)
    described_class.from_xml(<<~XML)
      <birthdate xmlns="http://eu.europa.ec/fpi/fsd/export" #{attributes}/>
    XML
  end

  # logicalId 1865 in the live export.
  let(:closed_span) do
    parse('circa="true" calendarType="GREGORIAN" ' \
          'city="Tirin Kot District, Uruzgan Province" ' \
          'yearRangeFrom="1953" yearRangeTo="1958" countryIso2Code="AF" ' \
          'countryDescription="AFGHANISTAN" logicalId="1865"')
  end

  # logicalId 117055 — the one record in the export that states an upper
  # bound and no lower one.
  let(:open_below) do
    parse('circa="false" calendarType="GREGORIAN" yearRangeTo="1980" ' \
          'countryIso2Code="ER" countryDescription="ERITREA" ' \
          'logicalId="117055"')
  end

  it 'reads both native attributes off the XML' do
    expect(closed_span.year_range_from).to eq(1953)
    expect(closed_span.year_range_to).to eq(1958)
  end

  it 'reads a bound that stands alone' do
    expect(open_below.year_range_to).to eq(1980)
    expect(open_below.year_range_from).to be_nil
  end

  it 'carries both bounds through the YAML fetch artifact' do
    restored = described_class.from_yaml(closed_span.to_yaml)

    expect(restored.year_range_from).to eq(1953)
    expect(restored.year_range_to).to eq(1958)
  end

  it 'carries a lone bound through the YAML fetch artifact' do
    restored = described_class.from_yaml(open_below.to_yaml)

    expect(restored.year_range_to).to eq(1980)
    expect(restored.year_range_from).to be_nil
  end

  # circa and the span are independent claims: the export carries both
  # settings alongside a span, so circa must not be read off the span.
  it 'keeps circa independent of the span, in both settings' do
    expect(closed_span.circa).to be true
    expect(open_below.circa).to be false
  end

  describe 'through the transformer, from the YAML artifact' do
    let(:transformer) { Ammitto::Sources::Eu::Transformer.new }

    def birth_from_yaml(birthdate)
      restored = described_class.from_yaml(birthdate.to_yaml)
      transformer.send(:transform_birthdates, [restored]).first
    end

    it 'lands both bounds in BirthInfo and claims no single year' do
      birth = birth_from_yaml(closed_span)

      expect(birth.year_range_from).to eq(1953)
      expect(birth.year_range_to).to eq(1958)
      expect(birth.year).to be_nil
      expect(birth.date).to be_nil
    end

    it 'preserves circa=true alongside the span' do
      expect(birth_from_yaml(closed_span).circa).to be true
    end

    it 'lands a lone upper bound without inventing a lower one' do
      birth = birth_from_yaml(open_below)

      expect(birth.year_range_to).to eq(1980)
      expect(birth.year_range_from).to be_nil
      expect(birth.year).to be_nil
    end

    it 'keeps the birth place on a span record' do
      expect(birth_from_yaml(closed_span).country).to eq('AFGHANISTAN')
    end

    it 'leaves an ordinary year-only record alone' do
      plain = parse('year="1962" countryIso2Code="AF"')
      birth = birth_from_yaml(plain)

      expect(birth.year).to eq(1962)
      expect(birth.year_range_from).to be_nil
      expect(birth.year_range_to).to be_nil
    end
  end
end
