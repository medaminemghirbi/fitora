module Web
  module Member
    # A member's own app (/member/…, MemberShellComponent): authGuard, then
    # memberGuard — a staff login belongs to its own half. Not salle-scoped
    # (MIGRATION_AUDIT §8.1): a member trains at one gym or a few, and picks
    # which one the app shows, remembered across visits in a cookie as the
    # Angular app remembers it in localStorage (MemberService).
    class BaseController < Web::BaseController
      GYM_COOKIE = :fitora_member_gym

      layout "web/member"

      before_action :require_member_session!

      helper_method :gym, :member_gyms

      private

      def require_member_session!
        return render(json: { error: "Unauthorized" }, status: :unauthorized) if !signed_in? && request.format.json?
        return sign_in_first unless signed_in?

        go_home unless current_client
      end

      # The gyms whose app this member can open (TenantRules#member_companies).
      def member_gyms
        member_companies
      end

      # MemberService#activeGym: the one picked, if they still belong to it —
      # a stale choice is forgotten, as the Angular app forgets it on the
      # API's 404 — else the first.
      def gym
        return @gym if defined?(@gym)

        chosen = cookies[GYM_COOKIE]
        @gym = member_companies.find { |c| c.id == chosen } || member_companies.first
        cookies.delete(GYM_COOKIE) if chosen.present? && @gym&.id != chosen
        @gym
      end

      # The member's gym's clock, as the API reads it for a member's login
      # (Api::V1::BaseController#in_gym_time_zone).
      def in_gym_time_zone(&action)
        zone = current_client && (gym || current_client.companies.first)&.time_zone
        Time.use_zone(zone || Time.zone, &action)
      end

      # The API's words for a refusal the page shows in a toast.
      def render_refusal(messages, status: :unprocessable_content)
        messages = Array(messages)
        render json: { error: messages.first || "Validation failed", errors: messages }, status: status
      end
    end
  end
end
