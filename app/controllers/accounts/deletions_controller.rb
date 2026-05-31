# frozen_string_literal: true

module Accounts
  # [REQ-FIT-AUTH-002] Multi-step account deletion with active-plan warning (D15).
  class DeletionsController < ApplicationController
    before_action :authenticate_user!

    def new
      @active_plan = current_user.active_plan?
    end

    def create
      session[:account_deletion_acknowledged] = true
      redirect_to confirm_account_deletion_path
    end

    def confirm
      unless session[:account_deletion_acknowledged]
        redirect_to account_deletion_path, alert: t("auth.account_deletion.restart")
        return
      end

      @active_plan = current_user.active_plan?
    end

    def destroy
      unless session[:account_deletion_acknowledged]
        redirect_to account_deletion_path, alert: t("auth.account_deletion.restart")
        return
      end

      unless current_user.valid_password?(deletion_params[:current_password])
        flash.now[:alert] = t("auth.account_deletion.invalid_password")
        @active_plan = current_user.active_plan?
        return render :confirm, status: :unprocessable_entity
      end

      unless deletion_params[:confirm_phrase] == t("auth.account_deletion.confirm_phrase_expected")
        flash.now[:alert] = t("auth.account_deletion.invalid_phrase")
        @active_plan = current_user.active_plan?
        return render :confirm, status: :unprocessable_entity
      end

      Workspace.discard!(session, request: request)
      user = current_user
      sign_out(:user)
      user.destroy!
      session.delete(:account_deletion_acknowledged)
      redirect_to root_path, notice: t("auth.account_deletion.done")
    end

    private

    def deletion_params
      params.require(:user).permit(:current_password, :confirm_phrase)
    end
  end
end
