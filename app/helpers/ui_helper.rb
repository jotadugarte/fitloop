# frozen_string_literal: true

# [REQ-FIT-UI-004] Visual helpers for architecture-studio UI.
module UiHelper
  LAYER_CHIP_PALETTE = %w[#2a4d7a #3d6a9e #4a7ab0 #526980 #5c6d82 #6b7d8f #4d6380 #3a5789].freeze

  def layer_chip_color(layer_name)
    LAYER_CHIP_PALETTE[Zlib.crc32(layer_name.to_s) % LAYER_CHIP_PALETTE.size]
  end

  def project_status_badge_class(status)
    "status-badge status-badge--#{status}"
  end

  def project_status_label(status)
    t("projects.status.#{status}", default: status.humanize)
  end

  def fitloop_nav_active?(*paths)
    paths.any? { |path| current_page?(path) }
  end
end
