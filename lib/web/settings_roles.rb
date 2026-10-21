module Web
  # SettingsRolesComponent's constants and lookups, for the server-rendered
  # matrix (settings-roles redraws with the same ones).
  module SettingsRoles
    # The permission catalogue by the part of the gym it touches; a key the
    # backend adds that is not listed lands in a trailing "other" group.
    GROUPS = [
      { id: "front", keys: %w[clients checkin bookings] },
      { id: "planning", keys: %w[sessions activities coaches spaces] },
      { id: "sales", keys: %w[contracts contract_types payments] },
      { id: "insights", keys: %w[reports revenue] }
    ].freeze
    # Flagged in the matrix: prices, money totals and who coaches.
    SENSITIVE = %w[coaches contract_types revenue].freeze
    # What require_admin! keeps for the admin whatever a role holds.
    ADMIN_RESERVED = %w[settings accounts salles subscription refunds member_removal exports].freeze

    # #groups, unsearched: each group's keys the catalogue has, then "other".
    def self.groups(catalog_keys)
      known = GROUPS.flat_map { |g| g[:keys] }
      groups = GROUPS.map { |g| { id: g[:id], keys: g[:keys].select { |k| catalog_keys.include?(k) } } }
      groups << { id: "other", keys: catalog_keys.reject { |k| known.include?(k) } }
      groups.reject { |g| g[:keys].empty? }
    end

    # #permLabel: the translation, or the catalogue's own name.
    def self.label(key, catalog)
      translated = translate("settings.perm_#{key}")
      translated == "settings.perm_#{key}" ? (catalog[key] || key) : translated
    end

    # #permHint: the translation, or nothing.
    def self.hint(key)
      translated = translate("settings.perm_hint_#{key}")
      translated == "settings.perm_hint_#{key}" ? "" : translated
    end

    def self.translate(key)
      Web::Translations.translate(key, {}, locale: I18n.locale)
    end
    private_class_method :translate
  end
end
