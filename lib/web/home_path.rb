module Web
  # Where a signed-in account lands: the Angular app's
  # AuthService#homeRouteForCurrentUser, worked out on the server with
  # everything known. The Angular version runs before /bootstrap has loaded,
  # so it sees no permissions and no onboarding and sends every admin to the
  # schedule (REL-04); the intended order its own comments describe is what
  # this implements (MIGRATION_AUDIT §10, B-01):
  #
  #   member → their app · superadmin → the console · address unconfirmed →
  #   the "check your inbox" screen · first sign-in unfinished → that form ·
  #   coach → their day · front desk → the desk · no salle → a page saying so ·
  #   admin with setup unfinished → onboarding · `reports` → the dashboard ·
  #   anyone else → the schedule
  #
  # Paths are the Angular routes; a path in a shell whose pages belong to one
  # salle (admin, desk, coach) carries it (MIGRATION_AUDIT §8). Whether a
  # path is served by Rails or still by Angular is not this module's
  # question — see Web::BaseController#go_home.
  module HomePath
    def self.for(user: nil, client: nil, impersonating: false)
      return "/member/home" if client
      return "/connexion" if user.nil?
      return "/superadmin/overview" if user.superadmin?
      return "/confirmation-email" if user.email_confirmation_pending? && !impersonating
      return "/premiere-connexion" if user.first_sign_in_pending? && !impersonating

      company = user.current_company
      # A login with no salle: nothing here can open one for it any more.
      return "/sans-salle" if company.nil?

      coach = user.staff? && user.staff_member&.coach?
      return shell(company, "coach", "today") if coach

      permissions = user.permission_keys
      return shell(company, "desk", "dashboard") if user.staff? && (permissions & %w[checkin bookings]).size == 2

      if user.admin?
        onboarding = company.onboarding_state.as_json
        return admin(company, "onboarding") unless onboarding[:complete] || onboarding[:dismissed]
      end

      admin(company, permissions.include?("reports") ? "dashboard" : "calendar")
    end

    def self.admin(company, page)
      shell(company, "admin", page)
    end

    def self.shell(company, shell, page)
      "/#{shell}/#{company.id}/#{page}"
    end
  end
end
