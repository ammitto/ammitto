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

  before do
    allow(Ammitto::Logger).to receive(:warn)
  end

  it 'reads Article 3s as the Russia regime closing ports and services, with no asset freeze' do
    subject_to = described_class.parse('Article 3s (Council Regulation 833/2014)')

    expect(subject_to.regime).to eq(code: 'RUSSIA', name: 'Russia/Ukraine')
    expect(subject_to.instrument[:identifier]).to eq('Council Regulation (EU) No 833/2014')
    expect(effect_types(subject_to.text)).to eq(%w[entry_ban service_prohibition])
    expect(subject_to).to be_fully_mapped
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

  it 'preserves an unfamiliar measure under a known regime and asks for mapping review' do
    subject_to = described_class.parse('Article 16 (Council Regulation 2016/44)')

    expect(subject_to.regime).to eq(code: 'LIBYA', name: 'Libya')
    expect(subject_to.effects).to eq([{ effect_type: 'other', scope: nil, description: 'Unmapped source measure: Article 16' }])
    expect(subject_to).not_to be_fully_mapped
    expect(Ammitto::Logger).to have_received(:warn).with(/unmapped measure.*Article 16.*review mapping/).once
  end

  it 'does not borrow a measure from a different regulation' do
    subject_to = described_class.parse('Article 3s (Council Regulation 2016/44)')

    expect(subject_to.effects).to eq([{ effect_type: 'other', scope: nil, description: 'Unmapped source measure: Article 3s' }])
  end

  it 'retains known effects when a combined list also names an unfamiliar measure' do
    subject_to = described_class.parse('Asset freeze + New measure + Port entry ban (Council Regulation 2017/1509)')

    expect(subject_to.effects).to eq(
      [{ effect_type: 'asset_freeze', description: 'Asset freeze' },
       { effect_type: 'other', scope: nil, description: 'Unmapped source measure: New measure' },
       { effect_type: 'entry_ban', description: 'Port entry ban' }]
    )
    expect(subject_to).not_to be_fully_mapped
  end

  it 'keeps an unfamiliar regulation literal without guessing a regime, URL or known-label effect' do
    subject_to = described_class.parse('Asset freeze (Council Regulation (EU) No. 9999/123)')

    expect(subject_to.regime).to be_nil
    expect(subject_to.instrument).to eq(identifier: 'Council Regulation (EU) No. 9999/123')
    expect(subject_to.effects).to eq([{ effect_type: 'other', scope: nil, description: 'Unmapped source measure: Asset freeze' }])
    expect(subject_to).not_to be_fully_mapped
    expect(Ammitto::Logger).to have_received(:warn).with(%r{unmapped regulation 9999/123.*review mapping}).once
  end

  it 'normalizes lookup whitespace, case, EU and No variants while retaining the source text' do
    text = " \u00a0asset\tFREEZE+PORT\u00a0ENTRY ban (council\tREGULATION (eu) No 2017/1509)\u00a0 "
    subject_to = described_class.parse(text)

    expect(subject_to.text).to eq(text)
    expect(subject_to.regime[:code]).to eq('DPRK')
    expect(subject_to.instrument[:identifier]).to eq('Council Regulation (EU) 2017/1509')
    expect(subject_to.effects.map { |effect| effect[:effect_type] }).to eq(%w[asset_freeze entry_ban])
    expect(Ammitto::Logger).not_to have_received(:warn)
  end

  it 'preserves unfamiliar clause spelling and warns once for a value without recording data loss' do
    text = '  New   measure + Second measure (Council Regulation 9999/123)  '
    allow(Ammitto::ParseFailureVisibility).to receive(:report)
    subject_to = described_class.parse(text)
    2.times { subject_to.effects }

    expect(subject_to.text).to eq(text)
    expect(subject_to.instrument).to eq(identifier: 'Council Regulation 9999/123')
    expect(subject_to.effects.map { |effect| effect[:description] }).to eq(
      ['Unmapped source measure: New   measure', 'Unmapped source measure: Second measure']
    )
    expect(Ammitto::Logger).to have_received(:warn).with(include(text.inspect)).once
    expect(Ammitto::ParseFailureVisibility).not_to have_received(:report)
  end

  it 'preserves a measure that mentions Council Regulation without citing another numbered instrument' do
    text = 'Disclosure of Council Regulation status (Council Regulation 2017/1509)'
    subject_to = described_class.parse(text)

    expect(subject_to.text).to eq(text)
    expect(subject_to.effects).to eq(
      [{ effect_type: 'other', scope: nil, description: 'Unmapped source measure: Disclosure of Council Regulation status' }]
    )
    expect(subject_to).not_to be_fully_mapped
    expect(Ammitto::Logger).to have_received(:warn).with(include(text.inspect)).once
  end

  ['Article 3s (Council Regulation 833/2014)', 'Article 3s Council Regulation 833/2014',
   'Article 3s Council Regulation (EU) No. 833/2014'].each do |clause|
    it "rejects embedded citation #{clause.inspect} rather than assigning it to the final regulation" do
      text = "#{clause} + Asset freeze (Council Regulation 2017/1509)"

      expect { described_class.parse(text) }.to raise_error(Ammitto::ParseError, /multiple legal citations/)
      expect(Ammitto::Logger).not_to have_received(:warn)
    end
  end

  ["\u200B", "\u2060\uFEFF", " \u200B \t", "\u0000", "\u0001\u200B"].each do |measure|
    it "rejects a clause made only of invisible control or format characters #{measure.inspect}" do
      expect { described_class.parse("#{measure} (Council Regulation 2017/1509)") }
        .to raise_error(Ammitto::ParseError, /empty measure clause/)
    end
  end

  it 'preserves meaningful internal format characters in unfamiliar source measures' do
    measure = "New\u200Dmeasure"
    subject_to = described_class.parse("#{measure} (Council Regulation 2017/1509)")

    expect(subject_to.measures).to eq([measure])
    expect(subject_to.effects.first[:description]).to eq("Unmapped source measure: #{measure}")
  end

  [nil, '', " \u00a0 ", 'Article 15', 'Article 15 (Council Regulation 2016/44',
   'Article 15 (Other Regulation 2016/44)', 'Article 15 (Council Regulation 2016/x)',
   '+ Article 15 (Council Regulation 2016/44)', 'Article 15 + (Council Regulation 2016/44)',
   'Article 15 ++ Article 16 (Council Regulation 2016/44)'].each do |text|
    it "refuses malformed source cell #{text.inspect}" do
      expect { described_class.parse(text) }.to raise_error(Ammitto::ParseError)
      expect(Ammitto::Logger).not_to have_received(:warn)
    end
  end
end
