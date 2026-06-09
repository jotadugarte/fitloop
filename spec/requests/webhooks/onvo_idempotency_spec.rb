# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO webhook concurrency and idempotency", "[REQ-FIT-BILL-001]", type: :request do
  let(:webhook_secret) { "whsec_test_onvo" }

  before do
    @previous_webhook_secret = ENV["ONVO_WEBHOOK_SECRET"]
    ENV["ONVO_WEBHOOK_SECRET"] = webhook_secret
  end

  after do
    if @previous_webhook_secret.nil?
      ENV.delete("ONVO_WEBHOOK_SECRET")
    else
      ENV["ONVO_WEBHOOK_SECRET"] = @previous_webhook_secret
    end
  end

  def prepare_pending_onvo_payment!(intent_id: "pi_webhook_concurrency")
    user = create_billing_user!(email: "onvo-concurrency@example.com")
    project = Project.create!(ephemeral: true, title: "Concurrency nest", status: :completed)
    run = project.nesting_runs.create!(status: "completed")
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF FOR CONCURRENCY"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    payment = Payment.create!(
      user: user,
      nesting_run: run,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: intent_id,
      onvo_mode: "test",
      gateway_status: "processing"
    )
    { payment: payment, run: run }
  end

  it "handles concurrent duplicate webhook payloads gracefully using pessimistic locking" do
    ctx = prepare_pending_onvo_payment!
    payment_intent_id = ctx[:payment].onvo_payment_intent_id
    payload = {
      type: "payment-intent.succeeded",
      data: { id: payment_intent_id, status: "succeeded" }
    }

    # Stub fulfill_single_download! to sleep, holding the database lock
    # on the payment record for the first request thread.
    original_fulfill = Billing::FulfillPayment.instance_method(:fulfill_single_download!)

    # We use a thread-safe counter/barrier to only sleep on the first execution
    call_count = Concurrent::AtomicFixnum.new(0)

    allow_any_instance_of(Billing::FulfillPayment).to receive(:fulfill_single_download!) do |instance|
      count = call_count.increment
      if count == 1
        # First thread holds the lock and sleeps
        sleep 0.5
      end
      original_fulfill.bind_call(instance)
    end

    # Spin up concurrent requests using separate integration sessions and threads
    session1 = open_session
    session2 = open_session

    threads = []
    responses = []

    # Thread 1 starts first
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        session1.post "/webhooks/onvo",
                     params: payload.to_json,
                     headers: {
                       "CONTENT_TYPE" => "application/json",
                       "X-Webhook-Secret" => webhook_secret
                     }
        responses << { thread: 1, status: session1.response.status, body: session1.response.body }
      end
    end

    # Give thread 1 a tiny head start to acquire the lock and enter the sleep block
    sleep 0.1

    # Thread 2 starts while thread 1 is sleeping
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        session2.post "/webhooks/onvo",
                     params: payload.to_json,
                     headers: {
                       "CONTENT_TYPE" => "application/json",
                       "X-Webhook-Secret" => webhook_secret
                     }
        responses << { thread: 2, status: session2.response.status, body: session2.response.body }
      end
    end

    threads.each(&:join)

    # Verify that only one DownloadGrant was created
    expect(DownloadGrant.where(user_id: ctx[:payment].user_id, nesting_run_id: ctx[:run].id).count).to eq(1)

    # Verify response statuses and bodies
    # One request should be :ok (empty body or success), and the other should be :already_fulfilled
    expect(responses.size).to eq(2)

    ok_resp = responses.find { |r| r[:status] == 200 && r[:body].blank? }
    dup_resp = responses.find { |r| r[:status] == 200 && r[:body].include?("already_fulfilled") }

    expect(ok_resp).to be_present
    expect(dup_resp).to be_present

    # Parse and verify the JSON of the duplicate response
    json_body = JSON.parse(dup_resp[:body])
    expect(json_body["status"]).to eq("already_fulfilled")
  end
end
