# frozen_string_literal: true

Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  get 'health', to: 'health#show'

  scope 'api/v1' do
    get 'statistics', to: 'statistics#show'
    get 'models', to: 'device_models#index'

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
