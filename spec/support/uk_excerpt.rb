# frozen_string_literal: true

# Real OFSI records (AFG0006, DPR0075, BEL0164) copied verbatim from the
# published UK-Sanctions-List.xml, so specs parse what the source ships.
module UkExcerpt
  PATH = File.expand_path('../fixtures/uk/designations_excerpt.xml', __dir__)

  def self.xml
    File.read(PATH)
  end

  def self.designations
    Ammitto::Sources::Uk::Designations.from_xml(xml)
  end

  def self.designation(unique_id)
    designations.items.find { |d| d.unique_id == unique_id }
  end
end
