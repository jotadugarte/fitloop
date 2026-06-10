# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::GuestContext, "[REQ-FIT-OPS-001]" do
  it "[REQ-FIT-OPS-001] builds metadata from the request" do
    request = instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10", user_agent: "RSpec")
    context = described_class.from_request(request: request, source_url: "https://example.com/taller")

    expect(context.to_h).to eq(
      "ip" => "203.0.113.10",
      "user_agent" => "RSpec",
      "source_url" => "https://example.com/taller"
    )
    expect(context).to eq(described_class.from_request(request: request, source_url: "https://example.com/taller"))
    expect(context.hash).to eq(described_class.from_request(request: request, source_url: "https://example.com/taller").hash)
  end

  it "[REQ-FIT-OPS-001] requires a request object" do
    expect { described_class.from_request(request: nil) }.to raise_error(ArgumentError, /request required/)
  end
end
