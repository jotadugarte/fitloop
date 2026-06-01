# frozen_string_literal: true

module Analytics
  module FunnelStages
    ORDERED = %w[
      workspace_started
      first_dxf_uploaded
      nest_completed
      paywall_viewed
      payment_succeeded
      download_completed
    ].freeze
  end
end
