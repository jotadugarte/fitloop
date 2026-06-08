# frozen_string_literal: true

class Rack::Attack
  # Use an in-memory store for rate limit states.
  # This makes it environment-agnostic (no external Redis dependency required for simple limits).
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Throttle authentication routes (sign in and sign up)
  # Limit to 5 requests per minute per IP.
  throttle("auth/ip", limit: 5, period: 1.minute) do |req|
    if req.path == "/iniciar-sesion" || req.path == "/crear-cuenta"
      if req.post?
        req.ip
      end
    end
  end

  # Throttle payment routes (checkout pay, sinpe confirmation, card confirmation)
  # Limit to 5 requests per minute per IP.
  throttle("payment/ip", limit: 5, period: 1.minute) do |req|
    if req.post?
      is_payment_path = req.path == "/checkout/pagar" ||
                        req.path.match?(%r{\A/checkout/pagos/[^/]+/sinpe\z}) ||
                        req.path.match?(%r{\A/checkout/pagos/[^/]+/tarjeta\z})

      if is_payment_path
        req.ip
      end
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |_env|
    [
      429,
      { "Content-Type" => "text/plain" },
      ["Retry later\n"]
    ]
  end
end
