# frozen_string_literal: true

module Admin
  class UsersController < Admin::BaseController
    def index
      @q = params[:q].to_s.strip
      @users = User.all
      if @q.present?
        query = Admin::IlikeSearch.pattern(@q.downcase)
        @users = @users.where(
          "LOWER(email) LIKE :query ESCAPE '\\' OR LOWER(name) LIKE :query ESCAPE '\\'",
          query: query
        )
      end
      @users = @users.order(:email)
    end

    def show
      @user = User.find(params[:id])
      @events = UserEvent.where(user_id: @user.id).order(occurred_at: :desc)
    end
  end
end
