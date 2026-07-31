# frozen_string_literal: true

require 'ammitto'
require 'ammitto/sources/tr'

# The fetch fix alone would keep both designees on disk and still lose one
# in the graph: harmonize reads each YAML file back and mints its IRIs
# here. These examples pin the graph half of that seam — that the
# transformer identifies a record by the same local_id the fetcher named
# its file after, so a record with its own file also gets its own node.
RSpec.describe Ammitto::Sources::Tr::Transformer do
  # Turkey's two organisations on "Sıra No" 187. The first is the one
  # already published as entity/tr/187.
  def dtsrc
    entity(name: 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)')
  end

  def dio
    entity(name: 'DEFENCE INDUSTRIES ORGANISATION (DIO)')
  end

  def entity(name:, reference_number: '187')
    Ammitto::Sources::Tr::SanctionedEntity.new(
      name: name, reference_number: reference_number,
      entity_type: 'entity'
    )
  end

  def transform(source)
    described_class.new.transform(source)
  end

  describe 'two organisations sharing one reference' do
    it 'gives each its own entity IRI' do
      ids = [dtsrc, dio].map { |src| transform(src)[:entity].id }

      expect(ids.uniq.size).to eq(2)
    end

    it 'gives each its own entry IRI' do
      ids = [dtsrc, dio].map { |src| transform(src)[:entry].id }

      expect(ids.uniq.size).to eq(2)
    end

    it 'leaves entity/tr/187 on the designee already published there' do
      expect(transform(dtsrc)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/187')
    end

    it 'does not let the other designee take that IRI' do
      expect(transform(dio)[:entity].id)
        .to eq('https://www.ammitto.org/entity/tr/' \
               'defence-industries-organisation-dio')
    end

    it 'points each entry at its own entity' do
      [dtsrc, dio].each do |source|
        result = transform(source)

        expect(result[:entry].entity_id).to eq(result[:entity].id)
      end
    end
  end

  describe 'provenance' do
    it 'keeps the number Turkey published on both records' do
      references = [dtsrc, dio].map do |source|
        transform(source)[:entity].source_references
                                  .map(&:reference_number)
      end

      expect(references).to all(include('187'))
    end
  end

  it 'mints an IRI from the reference where none is reserved' do
    source = entity(name: 'SOME ORGANISATION', reference_number: '42')

    expect(transform(source)[:entity].id)
      .to eq('https://www.ammitto.org/entity/tr/42')
  end
end
