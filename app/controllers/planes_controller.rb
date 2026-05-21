# frozen_string_literal: true

# [REQ-FIT-BILL-001] Plan pricing/checkout (stub until simulated checkout ships).
class PlanesController < ApplicationController
  include RequiresBillingConfirmation

  def show
    render :show
  end
end
