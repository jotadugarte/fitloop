# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dxf::Python do
  describe ".executable" do
    it "returns .venv python path if executable exists" do
      allow(File).to receive(:executable?).with(Rails.root.join(".venv/bin/python")).and_return(true)
      expect(described_class.executable).to eq(Rails.root.join(".venv/bin/python").to_s)
    end

    it "returns python3 if .venv python does not exist" do
      allow(File).to receive(:executable?).with(Rails.root.join(".venv/bin/python")).and_return(false)
      expect(described_class.executable).to eq("python3")
    end
  end

  describe ".subprocess_env" do
    it "returns environment map with PYTHONPATH" do
      expect(described_class.subprocess_env).to eq({ "PYTHONPATH" => Rails.root.to_s })
    end
  end
end
