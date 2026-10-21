module Web
  # What the Rails web UI serves today (MIGRATION_AUDIT §9.2): which shells
  # WEB_UI_SHELLS switches on. A path in a served shell is answered by Rails;
  # every other path is still the Angular app's, reached through the session
  # hand-off (Web::Handoff) once a shell is switched over in production.
  module Routing
    SALLE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

    # The shells whose pages belong to one salle carry it in the path
    # (MIGRATION_AUDIT §8.1); the member's app and the superadmin's console
    # keep their Angular URLs.
    SALLE_SHELLS = %w[admin desk coach].freeze

    SHELLS = {
      # The admin shell, and the public and account pages an admin signs in
      # through: whichever implementation serves the admin shell serves them.
      "admin" => [
        %r{\A/(connexion|inscription|mot-de-passe-oublie|verify-email|confirmation-email|account-locked)?\z},
        %r{\A/admin/setup-company\z},
        %r{\A/auth/(reset-password|accept-invitation)\z},
        %r{\A/admin/#{SALLE.source}(/|\z)}
      ],
      "desk" => [ %r{\A/desk/#{SALLE.source}(/|\z)} ],
      "coach" => [ %r{\A/coach/#{SALLE.source}(/|\z)} ],
      "member" => [ %r{\A/member(/|\z)} ],
      "superadmin" => [ %r{\A/superadmin(/|\z)} ]
    }.freeze

    def self.shells
      Rails.configuration.x.web_ui_shells
    end

    def self.shell?(name)
      shells.include?(name.to_s)
    end

    # Some shells still Angular's: a crossing between the two needs the
    # session carried over (MIGRATION_AUDIT §9.3). Once every shell is
    # served here, nothing is handed off.
    def self.transition?
      SHELLS.keys.any? { |shell| !shell?(shell) }
    end

    # A path in a shell Angular still serves: /desk/… while the desk is not
    # switched on, and so on. Those fall through to the SPA.
    def self.angular_shell_path?(path)
      shell = path.to_s[%r{\A/([a-z]+)(/|\z)}, 1]
      SHELLS.key?(shell) && !shell?(shell)
    end

    def self.served?(path)
      path = path.to_s.split("?").first
      SHELLS.any? { |shell, patterns| shell?(shell) && patterns.any? { |p| p.match?(path) } }
    end

    # A Rails path as the Angular app names it: the salle out of the path
    # (/admin/<salle>/clients → /admin/clients), and the salle itself, which
    # the Angular tab keeps in sessionStorage instead (active-company.ts).
    def self.angular(path)
      path, query = path.to_s.split("?", 2)
      match = path.match(%r{\A/(#{SALLE_SHELLS.join("|")})/(#{SALLE.source})(/.*)?\z})
      return [ [ path, query ].compact.join("?"), nil ] if match.nil?

      [ [ "/#{match[1]}#{match[3]}", query ].compact.join("?"), match[2] ]
    end
  end
end
