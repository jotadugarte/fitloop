Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

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
    registrations: "users/registrations",
    passwords: "users/passwords",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  get "fusionar-cuenta", to: "accounts/merges#new", as: :fusionar_cuenta
  post "fusionar-cuenta", to: "accounts/merges#create"
  delete "fusionar-cuenta", to: "accounts/merges#destroy", as: :cancel_fusionar_cuenta

  get "confirmacion", to: "confirmations#show", as: :email_confirmation_pending
  get "planes", to: "planes#show"
  get "checkout", to: "checkout#show"

  resource :locale, only: :update, controller: "locales"

  get "empezar", to: "projects#start", as: :start_project

  resources :projects, except: :destroy do
    member do
      patch :nesting_parameters
      patch :workspace
      get :nesting_sync
      get :nested_dxf
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
         as: :accept_project_orphan_split_proposal
    post "orphan_resolutions/:piece_key/split_proposal/reject",
         to: "split_proposals#reject",
         as: :reject_project_orphan_split_proposal
    post "orphan_resolutions/:piece_key/split_proposal/regenerate",
         to: "split_proposals#regenerate",
         as: :regenerate_project_orphan_split_proposal
  end
end
