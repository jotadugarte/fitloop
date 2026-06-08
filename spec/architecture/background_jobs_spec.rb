# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Background Job Architecture", type: :architecture do
  before { Rails.application.eager_load! }

  it "verifies config/queue.yml has valid array syntax for queues" do
    config_path = Rails.root.join("config/queue.yml")
    expect(File.exist?(config_path)).to be true
    
    config = YAML.safe_load(ERB.new(File.read(config_path)).result, aliases: true)
    expect(config).to be_a(Hash)
    
    config.each do |env, env_config|
      next unless env_config.is_a?(Hash) && env_config["workers"]
      env_config["workers"].each do |worker|
        expect(worker["queues"]).to be_an(Array)
        expect(worker["queues"]).not_to be_empty
      end
    end
  end

  it "verifies that each Job inheriting from ApplicationJob uses a configured queue" do
    config_path = Rails.root.join("config/queue.yml")
    config = YAML.safe_load(ERB.new(File.read(config_path)).result, aliases: true)
    
    configured_queues = config.values.flat_map do |env_config|
      next [] unless env_config.is_a?(Hash) && env_config["workers"]
      env_config["workers"].flat_map { |w| w["queues"] }
    end.map(&:to_s).uniq
    
    jobs = ApplicationJob.descendants
    expect(jobs).not_to be_empty
    
    jobs.each do |job_class|
      queue_name = job_class.queue_name.to_s
      expect(configured_queues).to include(queue_name), 
        "Job #{job_class.name} uses unconfigured queue '#{queue_name}'"
    end
  end
end
