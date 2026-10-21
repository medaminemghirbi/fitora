module Web
  # TeamComponent's computed values, for the server-rendered team page. The
  # team-page controller computes the same ones again in the browser.
  module TeamHelper
    # The capabilities worth naming on a row, most consequential first
    # (TeamComponent's PERMISSION_ORDER).
    TEAM_PERMISSION_ORDER = %w[revenue payments clients sessions bookings checkin].freeze
    # The built-in role capped at one active login per salle.
    TEAM_MODERATOR_ROLE_KEY = "moderator".freeze

    # TeamComponent#permissionSummary: "" for a coach (nothing shown).
    def team_permission_summary(permissions)
      return "" if permissions.nil?
      return ngt("team.access_everything") if TEAM_PERMISSION_ORDER.all? { |key| permissions.include?(key) }

      named = TEAM_PERMISSION_ORDER.select { |key| permissions.include?(key) }.map { |key| ngt("team.access_#{key}") }
      named.any? ? named.join(" · ") : ngt("team.access_nothing")
    end

    # TeamComponent#moderator: the member holding the salle's moderator role.
    def team_moderator(members)
      members.find { |m| m[:active] && m[:staff] && !m[:staff][:coach_id] && m[:staff][:role_key] == TEAM_MODERATOR_ROLE_KEY }
    end

    # #backofficeRoles: every role but "coach" and "admin".
    def team_backoffice_roles
      team_roles.reject { |r| %w[coach admin].include?(r[:key]) }
    end

    # #isRoleTaken: the moderator role while someone other than `except_id`
    # holds it.
    def team_role_taken?(role, moderator, except_id = nil)
      holder = moderator&.dig(:staff)
      role[:key] == TEAM_MODERATOR_ROLE_KEY && holder.present? && holder[:id] != except_id
    end

    def team_available_roles(moderator)
      team_backoffice_roles.reject { |r| team_role_taken?(r, moderator) }
    end
  end
end
