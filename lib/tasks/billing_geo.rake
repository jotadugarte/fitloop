# frozen_string_literal: true

namespace :billing do
  namespace :geo do
    desc "Verify billing geo prerequisites (Cloudflare + optional GeoLite2 MMDB)"
    task check: :environment do
      puts "Rails.env=#{Rails.env}"

      override = Billing::GeoPaymentDefaults.country_override
      if override.present?
        puts "FITLOOP_BILLING_COUNTRY_OVERRIDE=#{override} (forces billing country in all environments)"
      else
        puts "FITLOOP_BILLING_COUNTRY_OVERRIDE=(not set)"
      end

      if Rails.env.production?
        puts "Production: proxy Fitloop through Cloudflare so every request includes CF-IPCountry."
      end

      path = Billing::GeoLite2.database_path
      if path.blank?
        puts "GEOLITE2_COUNTRY_MMDB_PATH=(not set) — GeoLite2 fallback disabled."
        puts "  Run: bin/rails billing:geo:install_geolite2 (requires MAXMIND_LICENSE_KEY)"
      elsif Billing::GeoLite2.available?
        puts "GEOLITE2_COUNTRY_MMDB_PATH=#{path} (readable)"
        sample = Billing::GeoLite2.country_code_for_ip("8.8.8.8")
        puts "  Sample lookup 8.8.8.8 -> #{sample.inspect}"
      else
        puts "GEOLITE2_COUNTRY_MMDB_PATH=#{path} (file missing or unreadable)"
        abort "GeoLite2 database not found"
      end

      puts "Billing paths audited when CF-IPCountry is missing: #{Billing::GeoCountryAudit::BILLING_PATH_PATTERN.inspect}"
      puts "OK"
    end

    desc "Download GeoLite2-Country MMDB into storage/geoip (requires MAXMIND_LICENSE_KEY)"
    task install_geolite2: :environment do
      script = Rails.root.join("bin/download_geolite2_country.sh")
      abort "Missing #{script}" unless script.file?

      exec(script.to_s)
    end
  end
end
