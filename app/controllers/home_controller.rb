# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    Workspace.discard!(session)
    Workspace.purge_all_ephemeral!
  end
end
