# frozen_string_literal: true

# [REQ-FIT-UI-004] Visual helpers for architecture-studio UI.
module UiHelper
  def layer_chip_color(layer)
    if layer.respond_to?(:color) && layer.color.present?
      return layer.color
    end

    name = layer.is_a?(ProjectLayer) ? layer.layer_name : layer.to_s
    hue = Zlib.crc32(name) % 360
    "hsl(#{hue} 62% 46%)"
  end

  def nesting_run_status_label(status)
    t("nesting_run.status.#{status}", default: status.to_s.humanize)
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
