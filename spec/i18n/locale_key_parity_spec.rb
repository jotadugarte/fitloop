# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale key parity for es_panic [REQ-FIT-UI-005]" do
  def flatten_leaf_keys(node, prefix = "")
    case node
    when Hash
      node.flat_map { |key, value| flatten_leaf_keys(value, prefix.empty? ? key.to_s : "#{prefix}.#{key}") }
    else
      [ prefix ]
    end
  end

  def reference_es_leaf_keys
    path = Rails.root.join("config/locales/es.yml")
    root = YAML.safe_load_file(path, aliases: true)
    locale_tree = root.fetch("es")
    flatten_leaf_keys(locale_tree).sort
  end

  around do |example|
    I18n.with_locale(:es_panic) { example.run }
  end

  it "includes :es_panic in available locales" do
    expect(I18n.available_locales).to include(:es_panic)
  end

  it "resolves every es.yml leaf key without translation missing" do
    reference_es_leaf_keys.each do |key|
      translation = I18n.t(key)
      expect(translation).to be_present
      expect(translation).not_to start_with("translation missing")
    end
  end

  it "does not prefix welcome steps with ordinals (rendered inside HTML ol)" do
    %w[projects.setup.welcome.steps projects.show.welcome.steps].each do |key|
      Array(I18n.t(key)).each do |step|
        expect(step).not_to match(/\A\d+\.\s/)
      end
    end
  end
end
