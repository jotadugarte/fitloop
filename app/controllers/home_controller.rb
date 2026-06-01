# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    Workspace.discard!(session, request: request)
    Workspace.purge_all_ephemeral!
  end
end
