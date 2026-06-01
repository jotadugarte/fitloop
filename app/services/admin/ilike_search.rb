# frozen_string_literal: true

module Admin
  # Shared ILIKE wildcard escaping for admin search filters (see VentasFilter).
  module IlikeSearch
    module_function

    def escape(term)
      term.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
    end

    def pattern(term)
      "%#{escape(term)}%"
    end
  end
end
