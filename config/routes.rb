Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonguides.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#index"

  devise_for :users, path: "", path_names: {
    sign_in: "iniciar-sesion",
    sign_out: "cerrar-sesion",
    sign_up: "crear-cuenta",
    password: "contrasena",
    confirmation: "confirmacion",
    edit: "mi-cuenta"
  }, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  get "eliminar-cuenta", to: "accounts/deletions#new", as: :account_deletion
  post "eliminar-cuenta", to: "accounts/deletions#create"
  get "eliminar-cuenta/confirmar", to: "accounts/deletions#confirm", as: :confirm_account_deletion
  delete "eliminar-cuenta", to: "accounts/deletions#destroy"

  get "fusionar-cuenta", to: "accounts/merges#new", as: :fusionar_cuenta
  post "fusionar-cuenta", to: "accounts/merges#create"
  delete "fusionar-cuenta", to: "accounts/merges#destroy", as: :cancel_fusionar_cuenta

  get "terminos", to: "legal#terms", as: :terminos
  get "privacidad", to: "legal#privacy", as: :privacidad

  get "confirmacion-pendiente", to: "confirmations#show", as: :email_confirmation_pending
  get "planes", to: "planes#show"
  post "planes/simular", to: "planes#simulate", as: :planes_simulate
  get "checkout", to: "checkout#show"
  post "checkout/simular", to: "checkout#simulate", as: :checkout_simulate

  get "carrito", to: "cart#show", as: :cart

  get "mis-pagos", to: "mis_pagos#show", as: :mis_pagos
  get "mis-pagos/descargas/:id", to: "mis_pagos/downloads#show", as: :mis_pagos_download

  resource :locale, only: :update, controller: "locales"

  get "empezar", to: "projects#start", as: :start_project

  resolve("Project") { [:workshop] }

  # Ephemeral workshop (session-bound); no project id in the browser URL.
  resource :workshop, path: "taller", controller: "projects", only: %i[show edit update] do
    member do
      patch :nesting_parameters
      patch :workspace
      get :nesting_sync
      get :nested_dxf
      get "descarga-pago", to: "download_paywall#show", as: :download_paywall
      get "orphans/:piece_index/dxf",
          to: "project_orphan_dxf_downloads#show",
          as: :orphan_dxf
    end
    resources :layers, only: :index, controller: "project_layers" do
      patch "", on: :collection, action: :update
    end
    resources :input_dxf_files, only: %i[create destroy], controller: "project_input_dxf_files"
    resources :nesting_runs, only: :create do
      member do
        post :cancel
      end
    end
    resources :orphan_resolutions, only: :update, param: :piece_key do
      member do
        post :confirm_manual
      end
    end
    post "orphan_resolutions/:piece_key/split_proposal/accept",
         to: "split_proposals#accept",
         as: :accept_orphan_split_proposal
    post "orphan_resolutions/:piece_key/split_proposal/reject",
         to: "split_proposals#reject",
         as: :reject_orphan_split_proposal
    post "orphan_resolutions/:piece_key/split_proposal/regenerate",
         to: "split_proposals#regenerate",
         as: :regenerate_orphan_split_proposal
  end

  resources :projects, only: %i[index new create]

  # Legacy bookmarks: redirect old /projects/:id URLs to /taller.
  get "projects/:id", to: redirect("/taller")
  get "projects/:id/edit", to: redirect("/taller/edit")
  get "projects/:id/descarga-pago", to: redirect("/taller/descarga-pago")
  get "projects/:id/*path", to: redirect("/taller/%{path}")
end
