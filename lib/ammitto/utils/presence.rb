# frozen_string_literal: true

# Minimal presence predicates for the ontology layer, which calls
# #present?/#blank? throughout. Semantics match ActiveSupport exactly, and
# nothing is defined when ActiveSupport (or anything else) already provides
# them, so consumers loading both see no conflict.
unless Object.method_defined?(:blank?)
  class Object
    # @return [Boolean] true for nil, false, empty collections/strings
    def blank?
      respond_to?(:empty?) ? !!empty? : !self
    end
  end
end

unless Object.method_defined?(:present?)
  class Object
    # @return [Boolean] inverse of #blank?
    def present?
      !blank?
    end
  end
end

class String
  unless method_defined?(:blank?) && '  '.blank?
    # Whitespace-only strings are blank (Unicode whitespace included,
    # matching ActiveSupport)
    def blank?
      match?(/\A[[:space:]]*\z/)
    end
  end
end
