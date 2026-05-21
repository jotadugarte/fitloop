// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { configureTurboConfirm } from "fitloop_dialog"
import { configureWorkspaceTabLeave, configureWorkspaceTabHeaders } from "workspace_tab"
import "controllers"

configureTurboConfirm()
configureWorkspaceTabLeave()
configureWorkspaceTabHeaders()
