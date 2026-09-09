# frozen_string_literal: true

module Ammitto
  module Sources
    module Tr
      # The four Turkish lists, which law each falls under and which one
      # the extractor actually handles are in lib/ammitto/sources/tr.rb.
      # Raised when the workbook cannot be turned into records without
      # losing or misattributing one of them.
      #
      # Every condition that raises here is a case where continuing would
      # publish a corpus that is quietly wrong: a column silently
      # overwriting another column, two designees silently minting one
      # IRI, or a reserved IRI silently changing which designee it
      # denotes. Parsing completes before any of it is written, so a
      # refused harvest names the offending record and leaves the
      # previous corpus untouched.
      class IntegrityError < StandardError; end
    end
  end
end
