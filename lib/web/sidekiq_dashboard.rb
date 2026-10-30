module Web
  # Who may open the Sidekiq dashboard: HTTP basic auth against
  # SIDEKIQ_WEB_USER / SIDEKIQ_WEB_PASSWORD (config/routes.rb). Basic auth
  # answers every guess it is sent, so Rack::Attack asks here too, and shuts
  # out an address that keeps getting it wrong
  # (config/initializers/rack_attack.rb).
  #
  # The ban slows guessing down; a long password is what makes it hopeless.
  # A shorter one leaves the dashboard unmounted, with a warning at boot.
  module SidekiqDashboard
    MIN_PASSWORD_LENGTH = 24

    # Whether config/routes.rb mounts it: always in development, elsewhere
    # once a long enough password is set.
    def self.mount?(env = ENV)
      return true if Rails.env.development?
      return true if password_long_enough?(env)

      if env["SIDEKIQ_WEB_PASSWORD"].present?
        Rails.logger.warn("[sidekiq] SIDEKIQ_WEB_PASSWORD is shorter than #{MIN_PASSWORD_LENGTH} characters: /sidekiq is not mounted.")
      end
      false
    end

    def self.password_long_enough?(env = ENV) = env["SIDEKIQ_WEB_PASSWORD"].to_s.length >= MIN_PASSWORD_LENGTH

    def self.valid_credentials?(user, password)
      expected_user = ENV.fetch("SIDEKIQ_WEB_USER", "fitora")
      expected_pass = ENV["SIDEKIQ_WEB_PASSWORD"].to_s
      password_long_enough? &&
        ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(user.to_s), ::Digest::SHA256.hexdigest(expected_user)) &
          ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password.to_s), ::Digest::SHA256.hexdigest(expected_pass))
    end
  end
end
