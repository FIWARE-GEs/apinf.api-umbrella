Developer::Application.routes.draw do
  namespace :admin do resources :api_users end

  get "/doc/api-key" => "pages#api_key", :as => :doc_api_key
  get "/doc/errors" => "pages#errors"
  get "/doc/rate-limits" => "pages#rate_limits", :as => :doc_rate_limits

  get "/doc" => "api_doc_collections#index"
  get "/doc/api/:path" => "api_doc_services#show", :as => :api_doc_service, :constraints => {:path => /.*/}
  get "/doc/:slug" => "api_doc_collections#show", :as => :api_doc_collection

  get "/community" => "pages#community"

  resource :account, :only => [:create] do
    get "terms", :on => :collection
  end

  get "/signup" => "accounts#new"

  get "/contact" => "contacts#new"
  post "/contact" => "contacts#create"

  root :to => "pages#home"

  namespace :api do
    resources :api_users, :path => "api-users", :only => [:create]
  end

  devise_for :admins, :controllers => { :omniauth_callbacks => "admin/admins/omniauth_callbacks" } do
    resources :admin_sessions
    get "/admin/login" => "admin_sessions#new"
    get "/admin/logout" => "admin_sessions#destroy"
  end

  namespace :admin do
    resources :admins do
      get "page/:page", :action => :index, :on => :collection
    end

    resources :api_doc_services do
      get "page/:page", :action => :index, :on => :collection
    end

    resources :api_doc_collections do
      get "page/:page", :action => :index, :on => :collection
    end

    resources :api_users do
      get "page/:page", :action => :index, :on => :collection
    end
  end
end
