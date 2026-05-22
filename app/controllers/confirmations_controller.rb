# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Landing page for users who must confirm email before billing.
class ConfirmationsController < ApplicationController
  before_action :authenticate_user!

  def show
    precondition!(current_user.present?)
  end

  private

  def precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end
end
