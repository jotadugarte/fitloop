# frozen_string_literal: true

require "rails_helper"

RSpec.describe UiHelper, type: :helper do
  describe "#layer_chip_color" do
    it "returns the layer color if present" do
      layer = double("Layer", color: "#ff0000")
      allow(layer).to receive(:respond_to?).with(:color).and_return(true)
      expect(helper.layer_chip_color(layer)).to eq("#ff0000")
    end

    it "falls back to name generation if color is blank" do
      layer = double("Layer", color: "")
      allow(layer).to receive(:respond_to?).with(:color).and_return(true)
      allow(layer).to receive(:is_a?).with(ProjectLayer).and_return(false)
      allow(layer).to receive(:to_s).and_return("MyLayer")
      expect(helper.layer_chip_color(layer)).to start_with("hsl(")
    end

    it "handles ProjectLayer objects with name fallback" do
      project_layer = instance_double(ProjectLayer, color: nil, layer_name: "ProjectLayerName")
      allow(project_layer).to receive(:is_a?).with(ProjectLayer).and_return(true)
      expect(helper.layer_chip_color(project_layer)).to start_with("hsl(")
    end
  end

  describe "#nesting_run_status_label" do
    it "translates the nesting run status" do
      expect(helper).to receive(:t).with("nesting_run.status.completed", default: "Completed").and_return("Completado")
      expect(helper.nesting_run_status_label(:completed)).to eq("Completado")
    end
  end

  describe "#project_status_badge_class" do
    it "returns the badge class" do
      expect(helper.project_status_badge_class("active")).to eq("status-badge status-badge--active")
    end
  end

  describe "#project_status_label" do
    it "translates project status" do
      expect(helper).to receive(:t).with("projects.status.active", default: "Active").and_return("Activo")
      expect(helper.project_status_label("active")).to eq("Activo")
    end
  end

  describe "#fitloop_nav_active?" do
    it "returns true if one of the paths is current" do
      allow(helper).to receive(:current_page?).with("/path1").and_return(false)
      allow(helper).to receive(:current_page?).with("/path2").and_return(true)
      expect(helper.fitloop_nav_active?("/path1", "/path2")).to be(true)
    end

    it "returns false if none of the paths are current" do
      allow(helper).to receive(:current_page?).with("/path1").and_return(false)
      expect(helper.fitloop_nav_active?("/path1")).to be(false)
    end
  end
end
