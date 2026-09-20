# frozen_string_literal: true

Rails.application.routes.draw do
  # `/` is the public marketing website: plain static files under public/
  # (index.html, faq.html, css/, js/, images/, …), served by
  # ActionDispatch::Static before routing ever runs. There is deliberately no
  # root route here — adding one would shadow public/index.html.

  # Operator-facing recordings dashboard (formerly the site root). See
  # Admin::BaseController for its optional HTTP Basic auth.
  get 'admin', to: 'admin/dashboard#index', as: :admin_dashboard

  # The per-device personal panel, entered through a magic link the app
  # requests for itself (see PanelLinksController / PanelMagicLink).
  get 'panel', to: 'panel#show', as: :panel
  get 'panel/enter', to: 'panel#enter', as: :panel_enter
  match 'panel/sign-out', to: 'panel#sign_out', as: :panel_sign_out, via: %i[get delete]

  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  get 'health', to: 'health#show'

  scope 'api/v1' do
    get 'statistics', to: 'statistics#show'
    get 'models', to: 'device_models#index'

    post 'panel/magic-link', to: 'panel_links#create'

    # Specific /recordings/* routes must come before the /recordings/:id
    # routes below, since Rails matches routes top-to-bottom.
    get 'recordings/user/:user_id', to: 'recordings#by_user'
    get 'recordings/analytics/:user_id', to: 'recordings#analytics_by_user'
    get 'recordings/model/:model', to: 'recordings#by_model'
    get 'recordings/analytics-by-model/:model', to: 'recordings#analytics_by_model'

    get 'recordings', to: 'recordings#index'
    post 'recordings', to: 'recordings#create'
    get 'recordings/:id', to: 'recordings#show'
    put 'recordings/:id', to: 'recordings#update'
    delete 'recordings/:id', to: 'recordings#destroy'
  end

  match '*unmatched', to: 'application#route_not_found', via: :all
end
