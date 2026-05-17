# frozen_string_literal: true

# [REQ-FIT-UI-004] Visual helpers for architecture-studio UI.
module UiHelper
  def layer_chip_color(layer_name)
    hue = Zlib.crc32(layer_name.to_s) % 360
    "hsl(#{hue} 62% 46%)"
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
