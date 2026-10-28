module Web
  # Fitora's terms (CGU/CGV) and privacy policy — public, signed in or not,
  # linked from the landing page, the sign-up form and the member's app. The
  # French text is the one that binds; the English one is a translation,
  # and an Arabic reader gets the French with a note saying so.
  class LegalController < BaseController
    layout "web/auth"

    helper_method :legal_locale, :issuer

    def terms; end

    def privacy; end

    private

    def legal_locale
      locale_code.to_s == "en" ? "en" : "fr"
    end

    # Who publishes Fitora, as its invoices name it (Superadmin → Billing).
    def issuer
      @issuer ||= PlatformSetting.current
    end
  end
end
