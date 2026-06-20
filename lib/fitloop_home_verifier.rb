# frozen_string_literal: true

# Validates Rails 8 Fitloop app scaffold and home page (P0 step 3).
# After scaffold, also run: bundle exec rspec spec/requests/home_spec.rb
class FitloopHomeVerifier
  ROOT = File.expand_path("..", __dir__)

  REQUIRED_GEMFILE_GEMS = %w[
    rails
    pg
    turbo-rails
    stimulus-rails
    solid_queue
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    errors = []
    errors.concat(check_rails_app)
    errors.concat(check_gemfile)
    errors.concat(check_database)
    errors.concat(check_active_storage)
    errors.concat(check_i18n)
    errors.concat(check_home_route_and_views)
    errors.concat(check_request_spec)
    raise FitloopHomeError, errors.join("; ") if errors.any?

    true
  end

  private

  def check_rails_app
    errors = []
    errors << "missing config/application.rb (run rails new)" unless file?("config/application.rb")
    errors << "missing config/environment.rb" unless file?("config/environment.rb")
    errors
  end

  def check_gemfile
    return [ "missing Gemfile" ] unless file?("Gemfile")

    content = read("Gemfile")
    REQUIRED_GEMFILE_GEMS.filter_map do |gem_name|
      "Gemfile missing gem: #{gem_name}" unless content.include?(%("#{gem_name}"))
    end
  end

  def check_active_storage
    return [ "missing config/storage.yml (Active Storage)" ] unless file?("config/storage.yml")

    []
  end

  def check_database
    return [ "missing config/database.yml" ] unless file?("config/database.yml")

    content = read("config/database.yml")
    return [ "database.yml must use postgresql adapter" ] unless content.match?(/adapter:\s*postgresql/)

    []
  end

  def check_i18n
    errors = []
    %w[en es es_panic].each do |locale|
      path = "config/locales/#{locale}.yml"
      errors << "missing locale file: #{path}" unless file?(path)
    end
    errors
  end

  def check_home_route_and_views
    errors = []
    unless file?("config/routes.rb")
      errors << "missing config/routes.rb"
      return errors
    end

    routes = read("config/routes.rb")
    unless routes.match?(/root.*home#index|home#index.*root/)
      errors << "root route must point to home#index"
    end

    unless file?("app/controllers/home_controller.rb")
      errors << "missing app/controllers/home_controller.rb"
    end

    view_path = "app/views/home/index.html.erb"
    unless file?(view_path)
      errors << "missing #{view_path}"
      return errors
    end

    view = read(view_path)
    errors << "home view must include Fitloop branding" unless view.include?("Fitloop")
    unless view.match?(/image_tag|images\/|fitloop.*logo/i)
      errors << "home view must reference logo under images/"
    end

    errors
  end

  def check_request_spec
    path = "spec/requests/home_spec.rb"
    return [] unless file?(path)

    content = read(path)
    errors = []
    errors << "#{path} must tag REQ-FIT-APP-001" unless content.include?("REQ-FIT-APP-001")
    errors << "#{path} must request root_path" unless content.include?("root_path")
    errors << "#{path} must assert Fitloop in response body" unless content.match?(/Fitloop/)
    errors
  end

  def file?(relative)
    File.file?(File.join(ROOT, relative))
  end

  def read(relative)
    File.read(File.join(ROOT, relative))
  end
end

class FitloopHomeError < StandardError; end
