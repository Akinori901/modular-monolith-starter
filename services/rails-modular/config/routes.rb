# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    get "health", to: "health#show"
    get "health/live", to: "health#live"

    post "auth/sign-in", to: "sessions#create"
    get "auth/me", to: "sessions#show"

    post "files", to: "files#create"
    get "files/presign", to: "files#show"

    get "logs", to: "logs#index"
  end
end
