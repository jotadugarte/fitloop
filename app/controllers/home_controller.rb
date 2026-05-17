# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    Workspace.discard!(session)
  end
end
