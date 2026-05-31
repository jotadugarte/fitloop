# frozen_string_literal: true

module Workshop
  # [REQ-FIT-UI-001] Contextual Mi taller UI: setup vs full workshop.
  class UxMode
    def initialize(project)
      @project = project
    end

    def setup?
      @project.workshop_setup_mode?
    end

    def taller?
      !setup?
    end

    def show_preview_zone?
      taller?
    end

    def show_nesting_progress?
      taller?
    end

    def show_collapsed_nesting_parameters?
      taller?
    end

    def show_inline_nesting_settings?
      setup?
    end

    def open_sheet_inventory?
      setup?
    end

    def open_source_dxf_detail?
      setup?
    end

    def welcome_variant
      setup? ? :setup : :show
    end
  end
end
