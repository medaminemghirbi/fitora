module Web
  # What a throttled web form gets back (config/initializers/rack_attack.rb).
  # The API answers {error: "rate_limited"} as JSON; a page answers with
  # itself — the same form, refused with the words the Angular screen shows
  # for it — so the limits stay one budget shared by both doors.
  #
  # Rack::Attack runs after the session and cookies middleware, so the
  # controller action dispatched here has both, as in any request.
  module RateLimit
    ENV_KEY = "fitora.rate_limited".freeze

    def self.respond(request)
      status, headers, body = refusal(request)
      # When the window the request was counted in ends.
      if (match = request.env["rack.attack.match_data"])
        headers["Retry-After"] = (match[:period] - (match[:epoch_time] % match[:period])).to_s
      end
      [ status, headers, body ]
    end

    def self.refusal(request)
      return api_response if request.path.start_with?("/api/")

      env = request.env
      route = Rails.application.routes.recognize_path(request.path, method: request.request_method)
      return api_response unless route[:controller].to_s.start_with?("web/")

      env[ENV_KEY] = true
      env["action_dispatch.request.path_parameters"] = route
      "#{route[:controller].camelize}Controller".constantize.action(route[:action]).call(env)
    rescue ActionController::RoutingError
      api_response
    end

    # A new triplet each time: the middleware downstream writes into the
    # headers hash it is given.
    def self.api_response
      [ 429, { "Content-Type" => "application/json" }, [ { error: "rate_limited" }.to_json ] ]
    end
  end
end
