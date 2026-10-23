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
      before_action :require_confirmed_email!
      before_action :admin_area!
      before_action :enter_salle!
      before_action :refuse_when_locked!

      helper_method :admin_page_path, :nav, :may_sell?, :may_collect?

      # Which TenantRules::ADMIN_ALLOWED_WHEN_LOCKED area a controller is,
      # if any: a locked admin may still use those actions.
      class_attribute :lock_area, default: nil

      private

      def require_confirmed_email!
        go_home if email_confirmation_required?
      end

      # adminAreaGuard, in its order: the superadmin has a console of their
      # own; a locked gym sees one page; anyone who coaches uses the coach
      # shell. (The lock is asked again below for the salle the URL names.)
      def admin_area!
        return go_home if current_user.superadmin?
        return refuse_locked if locked_out?

        go_home if current_user.staff? && current_user.staff_member&.coach?
      end

      # adminAreaGuard's lock check: a locked gym sees one page.
      def refuse_when_locked!
        refuse_locked if locked_out?
      end

      def locked_out?
        locking_subscription(area: lock_area, action: action_name).present?
      end

      # A page goes to /account-locked; a page's own request (JSON) gets the
      # API's 402, which sends the page there (the jwt.interceptor's rule).
      def refuse_locked
        subscription = locking_subscription(area: lock_area, action: action_name)
        return redirect_to("/account-locked") unless request.format.json?

        render json: { error: subscription.lock_reason.to_s, message: lock_message(subscription) }, status: :payment_required
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
