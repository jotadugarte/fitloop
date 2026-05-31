# frozen_string_literal: true

module Nesting
  # [REQ-FIT-DOM-001] Parses workshop nesting parameter params into VOs before AR assign.
  class AssignNestingParameters
    Result = Struct.new(:ok?, :kerf, :margin, :errors, keyword_init: true)

    def self.call(raw_params:)
      new(raw_params: raw_params).call
    end

    def initialize(raw_params:)
      @raw_params = raw_params.to_h.symbolize_keys
    end

    def call
      kerf = KerfMm.parse(@raw_params[:kerf_mm])
      margin = MarginMm.parse(@raw_params[:margin_mm])
      Result.new(ok?: true, kerf: kerf, margin: margin, errors: [])
    rescue ArgumentError => error
      Result.new(ok?: false, kerf: nil, margin: nil, errors: [ error.message ])
    end
  end
end
