module Web
  # Everything set up once and rarely reopened, by what it is about: the gym,
  # how it runs, who may do what, and the login's own account. The menu, the
  # phone's picker and the page all read it from here.
  #
  # Most sections are drawn by Settings itself. A section with a `page` is a
  # page of its own, with its own address and guards (Web::SettingsPage), that
  # sits in this menu rather than the main one.
  class SettingsSections
    Section = Struct.new(:path, :page, :label_key, :desc_key, :keywords_key, :group, :admin_only, :permission, :feature, keyword_init: true) do
      # Where the menu takes you, under the salle.
      def target
        page || "settings/#{path}"
      end
    end
    Group = Struct.new(:key, :label_key, :sections, keyword_init: true)

    ALL = [
      Section.new(path: "company", label_key: "settings.nav_company", desc_key: "settings.desc_company", keywords_key: "settings.keywords_company", group: "gym", admin_only: true),
      Section.new(path: "legal", label_key: "settings.nav_legal", desc_key: "settings.desc_legal", keywords_key: "settings.keywords_legal", group: "gym", admin_only: true),
      Section.new(path: "branding", label_key: "settings.nav_branding", desc_key: "settings.desc_branding", keywords_key: "settings.keywords_branding", group: "gym", admin_only: true),
      Section.new(path: "spaces", page: "spaces", label_key: "nav.spaces", keywords_key: "settings.keywords_spaces", group: "gym", permission: "spaces", feature: "spaces"),
      Section.new(path: "salles", page: "salles", label_key: "nav.my_salles", keywords_key: "settings.keywords_salles", group: "gym", admin_only: true),
      Section.new(path: "planning", label_key: "settings.nav_planning", desc_key: "settings.desc_planning", keywords_key: "settings.keywords_planning", group: "operations", admin_only: true),
      Section.new(path: "booking", label_key: "settings.nav_booking", desc_key: "settings.desc_booking", keywords_key: "settings.keywords_booking", group: "operations", admin_only: true),
      Section.new(path: "catalogue", page: "catalogue", label_key: "nav.catalogue", keywords_key: "settings.keywords_catalogue", group: "operations", permission: "contract_types"),
      Section.new(path: "contracts", label_key: "settings.nav_contracts", desc_key: "settings.desc_contracts", keywords_key: "settings.keywords_contracts", group: "operations", admin_only: true),
      Section.new(path: "team", page: "team", label_key: "nav.team", keywords_key: "settings.keywords_team", group: "access", admin_only: true),
      Section.new(path: "roles", label_key: "settings.nav_roles", desc_key: "settings.desc_roles", keywords_key: "settings.keywords_roles", group: "access", admin_only: true),
      Section.new(path: "mobile-app", label_key: "settings.nav_mobile_app", desc_key: "settings.desc_mobile_app", keywords_key: "settings.keywords_mobile_app", group: "access", admin_only: true)
    ].freeze

    GROUP_ORDER = [ %w[gym settings.group_gym], %w[operations settings.group_operations], %w[access settings.group_access] ].freeze

    SECURITY = Section.new(path: "account", label_key: "settings.nav_account", desc_key: "settings.desc_account", keywords_key: "settings.keywords_account", group: "account")
    DISPLAY = Section.new(path: "appearance", label_key: "settings.appearance", desc_key: "settings.desc_appearance", keywords_key: "settings.keywords_appearance", group: "account")

    def initialize(user:, permissions:, features: nil)
      @user = user
      @permissions = Array(permissions)
      @features = (features || {}).to_h.with_indifferent_access
    end

    # The visible sections by group, then the login's own.
    def groups
      visible = ALL.select { |s| visible?(s) }
      grouped = GROUP_ORDER.map { |key, label| Group.new(key: key, label_key: label, sections: visible.select { |s| s.group == key }) }
                           .reject { |g| g.sections.empty? }
      grouped + [ Group.new(key: "account", label_key: "settings.group_account", sections: [ SECURITY, DISPLAY ]) ]
    end

    # Every section, in group order.
    def flat
      groups.flat_map(&:sections)
    end

    def find(path)
      flat.find { |s| s.path == path }
    end

    private

    def visible?(section)
      return false if section.feature && @features[section.feature] != true
      return true if @user.admin?
      return false if section.admin_only
      return true if section.permission.nil?

      @user.superadmin? || @permissions.include?(section.permission)
    end
  end
end
