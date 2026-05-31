# frozen_string_literal: true

module Admin
  class UsersController < Admin::BaseController
    def index
      @q = params[:q].to_s.strip
      @users = User.all
      if @q.present?
        # Search by email or name (case insensitive)
        @users = @users.where("LOWER(email) LIKE :query OR LOWER(name) LIKE :query", query: "%#{@q.downcase}%")
      end
      @users = @users.order(:email)
    end

    def show
      @user = User.find(params[:id])
      @events = UserEvent.where(user_id: @user.id).order(occurred_at: :desc)
    end
  end
end
