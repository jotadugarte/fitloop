# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Landing page for users who must confirm email before billing.
class ConfirmationsController < ApplicationController
  before_action :authenticate_user!

  def show
    head :ok
  end
end
