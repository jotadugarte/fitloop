# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

RSpec.describe "Importmap JavaScript pins", "[REQ-FIT-BILL-001]" do
  def importmap_imports
    stdout, status = Open3.capture2(Rails.root.join("bin/importmap").to_s, "json")
    expect(status).to be_success
    JSON.parse(stdout).fetch("imports")
  end

  def local_js_imports
    root = Rails.root.join("app/javascript")
    imports = Set.new

    Dir.glob(root.join("**/*.js")).each do |path|
      File.read(path).scan(/from\s+["']([^"']+)["']/) do |match|
        spec = match.first
        next if spec.start_with?("@") || spec.start_with?("controllers")
        next if spec.start_with?(".")

        imports << spec
      end
    end

    imports
  end

  it "[REQ-FIT-BILL-001] pins every local module imported from app/javascript" do
    imports = importmap_imports
    missing = local_js_imports.reject { |spec| imports.key?(spec) }

    expect(missing).to eq([]), "Add pin(s) in config/importmap.rb for: #{missing.sort.join(', ')}"
  end

  it "[REQ-FIT-BILL-001] pins ONVO checkout Stimulus dependencies" do
    imports = importmap_imports

    %w[
      controllers/onvo_checkout_controller
      controllers/onvo_payment_processing_controller
      controllers/mis_pagos_pending_sync_controller
      controllers/auto_download_controller
      checkout/onvo_checkout_validation
      checkout/onvo_checkout_card_draft
      checkout/onvo_checkout_sinpe_transfer
    ].each do |key|
      expect(imports).to have_key(key)
    end
  end
end
