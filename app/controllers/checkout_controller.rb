# frozen_string_literal: true

# [REQ-FIT-BILL-001] Single-run checkout (stub until simulated checkout ships).
class CheckoutController < ApplicationController
  include RequiresBillingConfirmation

  def show
    render :show
  end
end
