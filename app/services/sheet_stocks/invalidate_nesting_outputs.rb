# frozen_string_literal: true

module SheetStocks
  # Clear stale nesting artifacts after sheet inventory changes.
  class InvalidateNestingOutputs
    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      had_outputs = @project.nested_dxf.attached? || @project.placements_json.attached?
      return false unless had_outputs

      @project.nested_dxf.purge if @project.nested_dxf.attached?
      @project.placements_json.purge if @project.placements_json.attached?
      reset_terminal_status! if terminal_nesting_status?
      true
    end

    private

    def terminal_nesting_status?
      @project.completed? || @project.partial? || @project.failed?
    end

    def reset_terminal_status!
      @project.update!(status: :ready, progress_percent: nil, progress_message: nil)
    end
  end
end
