module Web
  # The root of the server-rendered web UI (MIGRATION_AUDIT_2026-10-15.md),
  # beside the API rather than under it: a session cookie instead of a bearer
  # token, pages and redirects instead of JSON — and the same rules, through
  # TenantRules, so neither front end can grant what the other refuses.
  class BaseController < ActionController::Base
    include TenantRules
    include Web::Authentication

    protect_from_forgery with: :exception

    # ?date= (or a form's date) that is not a date: the caller's mistake, not
    # a 500. Answered as the calendar answers it (CalendarController).
    rescue_from Date::Error, with: -> { render json: { error: "invalid date" }, status: :bad_request }

    # The Angular app's three languages and two themes, kept in cookies rather
    # than localStorage so the very first paint is already right (no flash of
    # the wrong language, direction or theme). See MIGRATION_AUDIT §11.3.
    LOCALES = %w[fr en ar].freeze
    DEFAULT_LOCALE = "fr" # LocaleService::DEFAULT_LOCALE
    LOCALE_COOKIE = :fitora_locale
    THEME_COOKIE = :fitora_theme

    around_action :with_locale
    around_action :in_gym_time_zone

    # A request Rack::Attack refused (Web::RateLimit): answered by the page's
    # own #rate_limited, in the page's language, before any of the
    # subclasses' callbacks run.
    before_action :rate_limited, if: -> { request.env[Web::RateLimit::ENV_KEY] }

    helper_method :locale_code, :rtl?, :theme, :bootstrap, :home_path, :live_notifications_for

    private

    def locale_code
      cookie = cookies[LOCALE_COOKIE].to_s
      LOCALES.include?(cookie) ? cookie : DEFAULT_LOCALE
    end

    def rtl?
      locale_code == "ar"
    end

    # ThemeService: light unless dark was chosen.
    def theme
      cookies[THEME_COOKIE] == "dark" ? "dark" : "light"
    end

    def remember_locale(code)
      return unless LOCALES.include?(code.to_s)

      cookies.permanent[LOCALE_COOKIE] = { value: code.to_s, same_site: :lax }
    end

    def with_locale(&action)
      I18n.with_locale(locale_code, &action)
    end

    # "Today", a day's end and "18:00 on Tuesday" mean the gym's local time,
    # as on the API (Api::V1::BaseController#in_gym_time_zone).
    def in_gym_time_zone(&action)
      Time.use_zone(current_company&.time_zone || Time.zone, &action)
    end

    # What the shell knows about this login — the same payload the mobile
    # app loads from /api/v1/bootstrap.
    def bootstrap
      @bootstrap ||= current_user && SessionBootstrap.new(current_user, current_company).as_json
    end

    def home_path
      Web::HomePath.for(user: current_user, client: current_client, impersonating: current_impersonator.present?)
    end

    def go_home
      redirect_to home_path
    end

    # No session: the sign-in page, as the Angular guards send there (no
    # return address, §8.3).
    def sign_in_first
      redirect_to web_sign_in_path
    end

    # The account a page's live notifications follow, or nil: a member, an
    # admin or a superadmin (NotificationService#connect). The live module
    # reconnects when it changes — after an impersonation starts or ends.
    def live_notifications_for
      return "client:#{current_client.id}" if current_client
      return "user:#{current_user.id}" if current_user && (current_user.admin? || current_user.superadmin?)

      nil
    end

    # A page with a form overrides this to show the form refused.
    def rate_limited
      head :too_many_requests
    end
  end
end
