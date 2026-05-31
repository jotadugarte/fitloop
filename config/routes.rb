Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonguides.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/onvo", to: "webhooks/onvo#create"

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
  post "checkout/pagar", to: "checkout#pay", as: :checkout_pay
  post "checkout/pagos/:payment_id/sinpe", to: "checkout#confirm_sinpe", as: :checkout_confirm_sinpe
  post "checkout/pagos/:payment_id/tarjeta", to: "checkout#confirm_card", as: :checkout_confirm_card
  get "checkout/procesando/:payment_id", to: "checkout#processing", as: :checkout_processing
  get "checkout/pagos/:payment_id/estado", to: "checkout#payment_status", as: :checkout_payment_status
  post "checkout/pagos/:payment_id/liberar", to: "checkout#release_pending_lock", as: :checkout_release_pending_lock
  get "checkout/pagos/:payment_id/cancelado", to: "checkout#payment_canceled_notice", as: :checkout_payment_canceled
  get "checkout/pagos/:payment_id/rechazado", to: "checkout#payment_failed_notice", as: :checkout_payment_failed
  get "checkout/retorno", to: "checkout#three_ds_return", as: :checkout_return

  get "carrito", to: "cart#show", as: :cart
  post "carrito", to: "cart#create"
  get "carrito/reemplazar", to: "cart#replace", as: :cart_replace
  delete "carrito/reemplazar", to: "cart#cancel_replace", as: :cart_replace_cancel
  patch "carrito", to: "cart#update"
  delete "carrito", to: "cart#destroy"

  get "mis-pagos", to: "mis_pagos#show", as: :mis_pagos
  get "mis-pagos/descargas/:id", to: "mis_pagos/downloads#show", as: :mis_pagos_download

  resource :locale, only: :update, controller: "locales"

  get "empezar", to: "projects#start", as: :start_project

  resolve("Project") { [:workshop] }

  # Ephemeral workshop (session-bound); no project id in the browser URL.
  resource :workshop, path: "taller", controller: "projects", only: %i[show] do
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

  get "taller/edit", to: redirect("/taller")

  resources :projects, only: %i[index]

  # Legacy bookmarks: redirect old /projects/:id URLs to /taller.
  get "projects/:id", to: redirect("/taller")
  get "projects/:id/edit", to: redirect("/taller")
  get "projects/:id/descarga-pago", to: redirect("/taller/descarga-pago")
  get "projects/:id/*path", to: redirect("/taller/%{path}")

  namespace :admin do
    root to: "dashboard#index"
    get "ventas", to: "ventas#index"
    get "ventas/exportar-xlsx", to: "ventas#export_xlsx", as: :export_ventas_xlsx
  end

  # Fallback redirects for relative admin path resolution
  get "taller/admin", to: redirect("/admin")
  get "mi-cuenta/admin", to: redirect("/admin")
end

