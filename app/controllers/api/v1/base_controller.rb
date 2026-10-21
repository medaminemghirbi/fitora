module Api
  module V1
    class BaseController < ApplicationController
      # The rules themselves (who may do what, in which salle, under which
      # plan and lock) are TenantRules, shared with the web UI. What stays
      # here is how the API says no: a JSON error and a status.
      include TenantRules

      before_action :authenticate_request!
      before_action :reject_member_token!
      before_action :require_confirmed_email!
      before_action :enforce_trial_lock!
      # After authentication, so it knows whose gym this is.
      around_action :in_gym_time_zone

      private

      # "Today", a day's end and "18:00 on Tuesday" mean the gym's local
      # time, not the server's UTC. Timestamps are still stored in UTC; only
      # what a date or a wall-clock time means changes.
      def in_gym_time_zone(&action)
        company = current_company || member_company || current_client&.companies&.first
        Time.use_zone(company&.time_zone || Time.zone, &action)
      end

      # A member's token has no business on a staff endpoint.
      #
      # Without this the refusal was incidental: most staff controllers call
      # require_company! early, which renders 422 because a client login has
      # no current_company — denied, but by accident and with a misleading
      # status. Worse, a controller whose capability check runs first would
      # reach `current_user.admin?` with current_user nil and raise.
      #
      # One gate, applied to every staff controller, so a new one is closed
      # by default. The member's own namespace (Api::V1::Me::*) is the single
      # exemption, and it gates on require_client! instead.
      def reject_member_token!
        return if current_client.nil?
        return if self.class.name.to_s.start_with?("Api::V1::Me::")

        render_forbidden
      end

      # An admin who signed up and has not clicked the link yet reaches
      # nothing here — not even naming their gym, which is where the trial
      # starts. What they need meanwhile (who am I, send it again) lives in
      # AuthController and EmailVerificationsController, outside this base.
      #
      # A superadmin impersonating them is let through: they are there to help,
      # and the address is not theirs to confirm.
      def require_confirmed_email!
        return unless email_confirmation_required?

        render json: {
          error: "email_unverified",
          message: "Confirm your email address to open your account. We sent the link to #{current_user.email}."
        }, status: :forbidden
      end

      # Which TenantRules::ADMIN_ALLOWED_WHEN_LOCKED area each controller is.
      LOCK_AREAS = {
        "Api::V1::SubscriptionController" => :subscription,
        "Api::V1::InvoicesController" => :invoices,
        "Api::V1::CompaniesController" => :companies
      }.freeze
      private_constant :LOCK_AREAS

      def enforce_trial_lock!
        subscription = locking_subscription(area: LOCK_AREAS[self.class.name], action: action_name)
        return if subscription.nil?

        render json: {
          error: subscription.lock_reason.to_s,
          message: lock_message(subscription)
        }, status: :payment_required
      end

      # For a member's login: the gym named by ?company_id=, checked against
      # the gyms whose app they can use. nil means "every such gym" —
      # almost always exactly one.
      def member_company
        return @member_company if defined?(@member_company)

        @member_company = if params[:company_id].present?
          member_companies.find { |c| c.id == params[:company_id].to_s }
        end
      end

      # The member app is a Pro feature: a member none of whose gyms is on
      # a paid Pro period has nothing to open.
      def require_member_app!
        return if member_companies.any?

        render json: {
          error: "member_app_not_included",
          message: "Your gym's plan does not include the member app."
        }, status: :forbidden
      end

      # Pro's tools (several salles, custom roles, branding, import / export):
      # open on a paid Pro period, refused on Starter and the trial with a code
      # the app turns into an upgrade prompt rather than a generic error.
      def require_pro!
        return if pro_access?

        render json: {
          error: "pro_required",
          message: "This feature comes with Fitora Pro."
        }, status: :forbidden
      end

      # 404 rather than 403: a gym the person has not joined should not even
      # be distinguishable from one that does not exist.
      def require_member_company!
        return if params[:company_id].blank? || member_company

        render json: { error: "Gym not found" }, status: :not_found
      end

      def require_admin!
        render_forbidden unless current_user.admin?
      end

      def require_superadmin!
        render_forbidden unless current_user.superadmin?
      end

      # Gates the member endpoints (Api::V1::Me::*) — the counterpart to
      # require_admin!/require_superadmin!, for the other kind of login.
      def require_client!
        render_forbidden if current_client.nil?
      end

      # The admin (always) or staff whose role grants this capability. For an
      # action that has to ask somewhere other than a before_action, use
      # TenantRules#capability? — render_forbidden does not halt, so calling
      # this mid-action would render twice.
      def require_capability!(capability)
        render_forbidden unless capability?(capability)
      end

      # Anyone with a seat in the company can see the calendar — the schedule is
      # shared operational context for every role. Editing sessions is a
      # separate, narrower check (require_capability!(:sessions)).
      def require_staff!
        render_forbidden unless staff_access?
      end

      # See TenantRules#schedule_reference_access?.
      def require_schedule_reference_read!(capability)
        render_forbidden unless schedule_reference_access?(capability)
      end

      def require_company!
        render json: { error: "No company found for this account" }, status: :unprocessable_content if current_company.nil?
      end

      def paginate(scope)
        page, per_page = page_params
        scope.limit(per_page).offset((page - 1) * per_page)
      end

      def pagination_meta(scope)
        page, per_page = page_params
        total = scope.count

        { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }
      end

      # ?page= from 1, ?per_page= 20 by default and never more than 100.
      def page_params
        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 20 if per_page <= 0
        [ page, [ per_page, 100 ].min ]
      end
    end
  end
end
