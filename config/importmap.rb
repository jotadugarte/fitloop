# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/checkout", under: "checkout"
pin "sheet_inventory_composer", to: "sheet_inventory_composer.js"
pin "fitloop_dialog", to: "fitloop_dialog.js"
pin "workspace_tab", to: "workspace_tab.js"
pin "sortablejs" # @1.15.7
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.1/dist/chart.js"
pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.2/dist/color.esm.js"
