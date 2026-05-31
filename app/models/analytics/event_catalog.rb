# frozen_string_literal: true

module Analytics
  class EventCatalog
    CATALOG_PATH = Rails.root.join("config/analytics_event_catalog.yml")

    def self.all_event_types
      load_catalog.keys
    end

    def self.priority_for(event_type)
      load_catalog.dig(event_type.to_s, "priority") || "low"
    end

    def self.required_properties_for(event_type)
      load_catalog.dig(event_type.to_s, "required_properties") || []
    end

    def self.load_catalog
      if File.file?(CATALOG_PATH)
        YAML.load_file(CATALOG_PATH) || {}
      else
        {}
      end
    end
  end
end
