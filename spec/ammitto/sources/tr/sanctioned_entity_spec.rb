# frozen_string_literal: true

require 'ammitto/sources/tr'

RSpec.describe Ammitto::Sources::Tr::SanctionedEntity do
  def entity(name:, reference_number: nil)
    described_class.new(name: name, reference_number: reference_number)
  end

  # The designee entity/tr/187 is already published for.
  def dtsrc(reference_number: '187')
    entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)',
           reference_number: reference_number)
  end

  # The designee Turkey gives the same number to, published nowhere.
  def dio(reference_number: '187')
    entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)',
           reference_number: reference_number)
  end

  describe '#local_id' do
    it 'is the reference Turkey published' do
      expect(entity(name: 'ACME', reference_number: '42').local_id)
        .to eq('42')
    end

    it 'ignores surrounding whitespace in the reference' do
      expect(entity(name: 'ACME', reference_number: ' 42 ').local_id)
        .to eq('42')
    end

    it 'is nil when Turkey published no reference' do
      expect(entity(name: 'ACME', reference_number: nil).local_id).to be_nil
      expect(entity(name: 'ACME', reference_number: '  ').local_id).to be_nil
    end

    it 'passes a non-decimal reference through untouched' do
      # The shape of an acceptable reference is PR #31's question; this
      # branch must not pre-empt it.
      expect(entity(name: 'ACME', reference_number: 'TR-1').local_id)
        .to eq('TR-1')
    end

    context 'when the reference is reserved for a published designee' do
      it 'keeps the number for the designee the IRI already denotes' do
        expect(dtsrc.local_id).to eq('187')
      end

      it 'gives the other claimant a name-derived id instead' do
        expect(dio.local_id).to eq('DEFENCE INDUSTRIES ORGANISATION (DIO)')
      end

      it 'resolves the same way whichever row is inspected first' do
        forwards = [dtsrc, dio].map(&:local_id)
        backwards = [dio, dtsrc].map(&:local_id).reverse

        expect(forwards).to eq(backwards)
        expect(forwards).to eq(['187',
                                'DEFENCE INDUSTRIES ORGANISATION (DIO)'])
      end

      it 'reserves the number even when nothing else claims it' do
        # A tie-break that only fired on a duplicate would let the other
        # designee inherit a published IRI the moment the holder was
        # renumbered away.
        expect(dio.local_id).not_to eq('187')
      end

      it 'leaves the holder alone under any other reference' do
        expect(dtsrc(reference_number: '900').local_id).to eq('900')
      end

      it 'refuses a name that would land in Turkey\'s own numbering' do
        # Otherwise a designee named "42" would take entity/tr/42 from
        # whoever Turkey numbered 42.
        expect(entity(name: '42', reference_number: '187').local_id).to be_nil
      end

      it 'is nil when the claimant carries no name to fall back to' do
        expect(entity(name: '  ', reference_number: '187').local_id).to be_nil
      end
    end
  end

  describe 'RESERVED_LOCAL_IDS' do
    it 'pins the reference to the sanitized name of its published holder' do
      slug = described_class::RESERVED_LOCAL_IDS.fetch('187')

      expect(Ammitto::Utils::IriSanitizer.sanitize(dtsrc.name)).to eq(slug)
    end

    it 'is frozen, so the reservation cannot drift at runtime' do
      expect(described_class::RESERVED_LOCAL_IDS).to be_frozen
    end
  end
end
