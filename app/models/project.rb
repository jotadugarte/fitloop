# frozen_string_literal: true

# [REQ-FIT-DOM-001] Nesting project with sheet inventory, layers, and job parameters.
# [REQ-FIT-AUTH-001] Ephemeral workspace projects; access via session bind (see ADR-0004).
class Project < ApplicationRecord
  attribute :ephemeral, :boolean, default: true

  scope :ephemeral, -> { where(ephemeral: true) }

  has_many :sheet_stocks, -> { order(:sort_order) }, dependent: :destroy, inverse_of: :project

  accepts_nested_attributes_for :sheet_stocks, allow_destroy: true
  has_many :project_layers, dependent: :destroy, inverse_of: :project
  has_many :nesting_runs, dependent: :destroy, inverse_of: :project
  has_many :orphan_resolutions, dependent: :destroy, inverse_of: :project
  has_many :derived_pieces, dependent: :destroy, inverse_of: :project
  has_many_attached :input_dxf
  has_one_attached :nested_dxf
  has_one_attached :placements_json

  enum :status, {
    draft: "draft",
    ready: "ready",
    processing: "processing",
    completed: "completed",
    partial: "partial",
    failed: "failed"
  }, default: :draft, validate: true

  validates :title, presence: true
  validates :kerf_mm, :margin_mm, :sheet_gap_mm,
            numericality: { greater_than_or_equal_to: 0 }
  validates :curve_tolerance_mm, numericality: { greater_than: 0 }
  validate :must_have_sheet_stocks, unless: :ephemeral?
  validate :at_most_one_unlimited_sheet_stock
  validate :validate_input_dxf_files

  # [REQ-FIT-SPLIT-001] Show dedicated re-nest CTA after accepted splits materialize derived pieces.
  def nest_with_updated_pieces_available?
    derived_pieces.exists? && (completed? || partial?)
  end

  # [REQ-FIT-UI-001] Setup onboarding on /taller before the first nesting run.
  def workshop_setup_mode?
    draft? && !nesting_runs.exists?
  end

  def metadata_snapshot
    {
      title: title,
      kerf_mm: kerf_mm,
      margin_mm: margin_mm,
      curve_tolerance_mm: curve_tolerance_mm,
      sheet_gap_mm: sheet_gap_mm,
      nesting_time_limit_sec: nesting_time_limit_sec,
      sheet_stocks: sheet_stocks.map { |s| { width_mm: s.width_mm, height_mm: s.height_mm, quantity: s.quantity } },
      layers_count: project_layers.count,
      included_layers: project_layers.where(included: true).pluck(:layer_name)
    }
  end

  private

  def must_have_sheet_stocks
    return if sheet_stocks.reject(&:marked_for_destruction?).any?

    errors.add(:base, :no_sheet_stocks)
  end

  # [REQ-FIT-DOM-001] At most one SheetStock with quantity nil (∞) per project.
  def at_most_one_unlimited_sheet_stock
    active_stocks = sheet_stocks.reject(&:marked_for_destruction?)
    unlimited_count = active_stocks.count { |stock| stock.quantity.nil? }
    return if unlimited_count <= 1

    errors.add(:base, :multiple_unlimited_sheet_stocks)
  end

  def validate_input_dxf_files
    # 1. Check unsaved files in attachment_changes
    changes = attachment_changes["input_dxf"]
    if changes
      changes.attachables.each do |attachable|
        io = nil
        filename = "file.dxf"

        if attachable.is_a?(Hash)
          io = attachable[:io]
          filename = attachable[:filename] || "file.dxf"
        elsif attachable.respond_to?(:tempfile)
          io = attachable.tempfile
          filename = attachable.original_filename
        elsif attachable.respond_to?(:download)
          begin
            io = StringIO.new(attachable.download)
            filename = attachable.filename.to_s
          rescue ActiveStorage::FileNotFoundError
            io = StringIO.new("")
            filename = attachable.filename.to_s
          end
        end

        next unless io

        size = io.respond_to?(:size) ? io.size : (io.respond_to?(:length) ? io.length : 0)
        if size > 10.megabytes
          errors.add(:input_dxf, :too_large, message: I18n.t("project_layers.upload.too_large", filename: filename.to_s))
        end

        unless filename.to_s.downcase.end_with?(".dxf")
          errors.add(:input_dxf, :invalid_extension, message: I18n.t("project_layers.upload.invalid_extension", filename: filename.to_s))
        end

        if size <= 10.megabytes
          io.rewind if io.respond_to?(:rewind)
          content = io.read(1024) || ""
          io.rewind if io.respond_to?(:rewind)
          unless content.include?("SECTION")
            errors.add(:input_dxf, :corrupt_dxf, message: I18n.t("project_layers.upload.corrupt_dxf", filename: filename.to_s))
          end
        end
      end
    end

    # 2. Check already persisted files
    input_dxf.attachments.each do |attachment|
      blob = attachment.blob
      next unless blob
      next if blob.new_record? # Handled in changes check

      if blob.byte_size > 10.megabytes
        errors.add(:input_dxf, :too_large, message: I18n.t("project_layers.upload.too_large", filename: blob.filename.to_s))
      end

      unless blob.filename.to_s.downcase.end_with?(".dxf")
        errors.add(:input_dxf, :invalid_extension, message: I18n.t("project_layers.upload.invalid_extension", filename: blob.filename.to_s))
      end

      if blob.byte_size <= 10.megabytes
        begin
          has_section = false
          blob.open do |tempfile|
            content = tempfile.read(1024) || ""
            has_section = content.include?("SECTION")
          end
          unless has_section
            errors.add(:input_dxf, :corrupt_dxf, message: I18n.t("project_layers.upload.corrupt_dxf", filename: blob.filename.to_s))
          end
        rescue ActiveStorage::FileNotFoundError
          errors.add(:input_dxf, :corrupt_dxf, message: I18n.t("project_layers.upload.corrupt_dxf", filename: blob.filename.to_s))
        end
      end
    end
  end
end
