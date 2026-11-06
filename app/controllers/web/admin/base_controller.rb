module Web
  module Admin
    # The admin shell (/admin/<salle>/…): the guards the Angular /admin
    # route stacks up, in the order it stacks them (app.routes.ts) —
    # authGuard, emailConfirmedGuard, adminAreaGuard, companyGuard — then the
    # salle the URL names (Web::SalleShell), then the page's own capability.
    class BaseController < Web::BaseController
      include Web::SalleShell

      layout "web/admin"

      before_action :require_staff_session!
      before_action :require_account_ready!
      before_action :admin_area!
      before_action :enter_salle!

      helper_method :admin_page_path, :nav, :may_sell?, :may_collect?

      private

      # The address to confirm and the first sign-in to finish come first.
      def require_account_ready!
        go_home if email_confirmation_required? || first_sign_in_required?
      end

      # adminAreaGuard, in its order: the superadmin has a console of their
      # own; anyone who coaches uses the coach shell.
      def admin_area!
        return go_home if current_user.superadmin?

        go_home if current_user.staff? && current_user.staff_member&.coach?
      end

      # capabilityGuard(permission): a page this login may not open sends it
      # home, as the Angular guard does.
      def require_capability(capability)
        go_home unless capability?(capability)
      end

      # roleGuard("admin"): the page is the admin's; anyone else goes home.
      def require_admin
        go_home unless current_user.admin?
      end

      def admin_page_path(page, query = {})
        path = "/admin/#{salle.id}/#{page}"
        query.compact_blank.empty? ? path : "#{path}?#{query.compact_blank.to_query}"
      end

      def nav
        @nav ||= Web::Navigation.new(user: current_user, bootstrap: bootstrap, salle: salle)
      end

      # Selling, renewing or changing a subscription is `contracts`; taking
      # the money for it is `payments` — what the subscription dialogs offer.
      def may_sell?
        capability?(:contracts)
      end

      def may_collect?
        capability?(:payments)
      end

      # A refusal in the page's language when the model named its reason
      # (ApplicationRecord::Refused#key), in the API's words otherwise.
      def refusal_message(refusal)
        return refusal.message if refusal.key.blank?

        params = refusal.params.transform_values do |value|
          value.is_a?(Date) || value.is_a?(Time) ? Web::DateFormat.angular(value.in_time_zone, "d MMM y", locale: locale_code) : value
        end
        page_words(refusal.key, **params)
      end

      # ngt, in the page's language even where the request's own has been
      # put back — a rescue_from handler runs after the around_action that
      # set it (Web::BaseController#with_locale) has returned.
      def page_words(key, **params)
        Web::Translations.translate(key, params, locale: locale_code)
      end
    end
  end
end
