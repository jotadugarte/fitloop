# frozen_string_literal: true

module Nesting
  # Raised when a nesting run is cancelled while executing.
  class CancelledError < StandardError; end
end
