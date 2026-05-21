# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "sheet_inventory_composer", to: "sheet_inventory_composer.js"
pin "fitloop_dialog", to: "fitloop_dialog.js"
pin "sortablejs" # @1.15.7
