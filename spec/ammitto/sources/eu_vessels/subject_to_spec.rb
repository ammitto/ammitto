# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/eu_vessels/subject_to'

module EuVesselsSubjectToSpecHelpers
  def effect_types(text)
    described_class.parse(text).effects.map { |e| e[:effect_type] }
  end
end

RSpec.describe Ammitto::Sources::EuVessels::SubjectTo do
  include EuVesselsSubjectToSpecHelpers

  it 'reads Article 3s as the Russia regime closing ports and services, with no asset freeze' do
    subject_to = described_class.parse('Article 3s (Council Regulation 833/2014)')

    expect(subject_to.regime).to eq(code: 'RUSSIA', name: 'Russia/Ukraine')
    expect(subject_to.instrument[:identifier]).to eq('Council Regulation (EU) No 833/2014')
    expect(effect_types(subject_to.text)).to eq(%w[entry_ban service_prohibition])
  end

  {
    'Asset freeze' => %w[asset_freeze],
    'Seizure' => %w[other],
    'Port entry ban' => %w[entry_ban],
    'De-registration' => %w[other],
    'De-registration + Port entry ban' => %w[other entry_ban]
  }.each do |measure, types|
    it "reads \"#{measure}\" under 2017/1509 as the DPRK regime with #{types.join(' and ')}" do
      subject_to = described_class.parse("#{measure} (Council Regulation 2017/1509)")

      expect(subject_to.regime[:code]).to eq('DPRK')
      expect(effect_types(subject_to.text)).to eq(types)
    end
  end

  it 'keeps DMA\'s words for a measure the ontology has no type for' do
    effects = described_class.parse('Seizure (Council Regulation 2017/1509)').effects

    expect(effects).to eq([{ effect_type: 'other', description: 'Seizure' }])
  end

  it 'retains the Libya Article 15 basis without assuming every conditional prohibition applies' do
    subject_to = described_class.parse('Article 15 (Council Regulation 2016/44)')

    expect(subject_to.regime).to eq(code: 'LIBYA', name: 'Libya')
    expect(subject_to.instrument).to eq(
      identifier: 'Council Regulation (EU) 2016/44',
      url: 'https://eur-lex.europa.eu/eli/reg/2016/44/oj'
    )
    expect(subject_to.effects).to eq([{ effect_type: 'other', description: 'Article 15' }])
  end

  it 'refuses an unmapped measure under the recognized Libya regulation' do
    expect { described_class.parse('Article 16 (Council Regulation 2016/44)') }
      .to raise_error(Ammitto::ParseError, %r{measure\(s\) Article 16, not mapped under 2016/44})
  end

  it 'does not borrow a measure from a different regulation' do
    expect { described_class.parse('Article 3s (Council Regulation 2016/44)') }
      .to raise_error(Ammitto::ParseError, %r{measure\(s\) Article 3s, not mapped under 2016/44})
  end

  it 'refuses a measure it has no mapping for' do
    expect { described_class.parse('Travel ban (Council Regulation 2017/1509)') }
      .to raise_error(Ammitto::ParseError, /measure\(s\) Travel ban/)
  end

  it 'refuses a regulation it has no mapping for' do
    expect { described_class.parse('Asset freeze (Council Regulation 269/2014)') }
      .to raise_error(Ammitto::ParseError, %r{regulation 269/2014})
  end

  it 'refuses an empty cell' do
    expect { described_class.parse(nil) }.to raise_error(Ammitto::ParseError, /""/)
  end
end
