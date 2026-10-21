module Web
  # The settings sections (settings-sections.ts, SettingsSectionsService):
  # the shell's tabs, its "Outils Pro" menu and its phone picker, filtered
  # the way the service filters them.
  class SettingsSections
    Section = Struct.new(:path, :icon, :label_key, :desc_key, :group, :admin_only, :permission, :pro, :short_key, keyword_init: true)
    Group = Struct.new(:key, :label_key, :sections, keyword_init: true)

    ALL = [
      Section.new(path: "company", icon: "bi-building", label_key: "settings.nav_company", desc_key: "settings.desc_company", group: "establishment", admin_only: true),
      Section.new(path: "branding", icon: "bi-palette", label_key: "settings.nav_branding", desc_key: "settings.desc_branding", group: "establishment", admin_only: true, pro: true, short_key: "settings.short_branding"),
      Section.new(path: "contracts", icon: "bi-file-earmark-text", label_key: "settings.nav_contracts", desc_key: "settings.desc_contracts", group: "establishment", admin_only: true),
      Section.new(path: "planning", icon: "bi-calendar3", label_key: "settings.nav_planning", desc_key: "settings.desc_planning", group: "planning", admin_only: true),
      Section.new(path: "booking", icon: "bi-journal-check", label_key: "settings.nav_booking", desc_key: "settings.desc_booking", group: "planning", admin_only: true),
      Section.new(path: "roles", icon: "bi-shield-lock", label_key: "settings.nav_roles", desc_key: "settings.desc_roles", group: "hr", admin_only: true, pro: true, short_key: "settings.short_roles"),
      Section.new(path: "data-exchange", icon: "bi-arrow-down-up", label_key: "nav.data_exchange", desc_key: "settings.desc_data_exchange", group: "establishment", admin_only: true, pro: true, short_key: "settings.short_data_exchange"),
      Section.new(path: "mobile-app", icon: "bi-phone", label_key: "settings.nav_mobile_app", desc_key: "settings.desc_mobile_app", group: "establishment", admin_only: true, pro: true, short_key: "settings.short_mobile_app")
    ].freeze

    GROUP_ORDER = [ %w[establishment settings.group_establishment], %w[planning settings.group_planning], %w[hr settings.group_hr] ].freeze

    APPEARANCE = Section.new(path: "appearance", icon: "bi-circle-half", label_key: "settings.appearance", desc_key: "settings.desc_appearance", group: "appearance")
    ACCOUNT = Section.new(path: "account", icon: "bi-person-lock", label_key: "settings.nav_account", desc_key: "settings.desc_account", group: "appearance")

    def initialize(user:, permissions:)
      @user = user
      @permissions = Array(permissions)
    end

    # #navGroups: the visible sections by group, then "Apparence".
    def groups
      visible = ALL.select { |s| visible?(s) }
      grouped = GROUP_ORDER.map { |key, label| Group.new(key: key, label_key: label, sections: visible.select { |s| s.group == key }) }
                           .reject { |g| g.sections.empty? }
      grouped + [ Group.new(key: "appearance", label_key: "settings.group_appearance", sections: [ APPEARANCE, ACCOUNT ]) ]
    end

    # Every section, in group order (the shell's `flat`).
    def flat
      groups.flat_map(&:sections)
    end

    def core
      flat.reject(&:pro)
    end

    def pro
      flat.select(&:pro)
    end

    def find(path)
      flat.find { |s| s.path == path }
    end

    private

    def visible?(section)
      return true if @user.admin?
      return false if section.admin_only
      return true if section.permission.nil?

      @user.superadmin? || @permissions.include?(section.permission)
    end
  end
end
