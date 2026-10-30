# Be sure to restart your server when you modify this file.

# Allows the mobile app's Expo web dev server (and any origin listed in
# FRONTEND_ORIGINS) to call this API cross-origin. The web UI is served from
# the API's own origin and the native app sends no Origin: neither needs it.
# In production, only what FRONTEND_ORIGINS lists, and none when it is unset:
# a deployed API has no business answering a page on someone's localhost.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGINS") { Rails.env.production? ? "" : "http://localhost:8081" }.split(",")

    resource "/api/*",
      headers: :any,
      expose: [ "Authorization" ],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
