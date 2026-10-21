module Web
  # The admin shell's small decisions, as its Angular components make them.
  module ShellHelper
    # RouterLinkActive with its default options: the link's path is a
    # segment-wise prefix of the current one, and its query parameters are a
    # subset of the current ones ("/admin/…/clients" is active on a client's
    # file; "…/payments?action=new" only with that parameter).
    def shell_active?(item)
      link = nav.path(item)
      link_path, link_query = link.split("?", 2)
      current = request.path.split("/").reject(&:empty?)
      wanted = link_path.split("/").reject(&:empty?)
      return false unless current.first(wanted.size) == wanted

      Rack::Utils.parse_query(link_query.to_s).all? { |key, value| request.query_parameters[key] == value }
    end

    # RailComponent#roleLabelKey: who you are in this gym — a translation key,
    # or a role's own name (which `ngt` passes through, as the pipe does).
    def shell_role_label
      user = bootstrap[:user]
      return "nav.role_admin" if user[:role] == "admin"
      return "nav.role_coach" if user[:is_coach]
      return "nav.role_staff" if user[:staff_role].blank?

      role = Array(bootstrap[:roles]).find { |r| r[:key] == user[:staff_role] }
      role ? role[:name] : user[:staff_role].to_s.capitalize
    end

    # BrandingService#apply: the tenant's colour as the primary one, its hover
    # and soft shades mixed from it — set on <html>, as the service sets
    # them on document.documentElement. nil without a colour.
    def shell_brand_style
      color = bootstrap&.dig(:branding, :primary_color).presence
      return nil if color.nil?

      "--color-primary: #{color}; --color-primary-hover: color-mix(in srgb, #{color} 80%, var(--color-text)); " \
        "--color-primary-soft: color-mix(in srgb, #{color} 15%, var(--color-surface));"
    end

    # AppVersionService: the latest published release, if any.
    def shell_version
      @shell_version = AppUpdate.recent.first&.version unless defined?(@shell_version)
      @shell_version
    end

    # NavbarComponent#activePageLabel: the most specific entry the current
    # path is under — the page's name next to the burger on a phone.
    def shell_page_label_key
      nav.leaves.select { |item| request.path.start_with?(nav.path(item).split("?").first) }
         .max_by { |item| nav.path(item).length }&.label_key
    end

    # NavbarComponent#switchableCompanies: an admin always sees the
    # switcher (it is also their way to "Mes salles"); a moderator once
    # posted to more than one salle.
    def shell_switchable_companies
      user = bootstrap[:user]
      companies = user[:companies]
      return nil if companies.blank?

      user[:role] == "admin" || companies.size > 1 ? companies : nil
    end

    def shell_active_company
      shell_switchable_companies&.find { |c| c[:active] }
    end

    def shell_can_switch?
      (shell_switchable_companies&.size || 0) > 1 && nav.pro_features?
    end

    def shell_switch_locked?
      shell_switchable_companies.present? && !nav.pro_features?
    end
  end
end
