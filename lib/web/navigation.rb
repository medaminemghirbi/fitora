module Web
  # The admin shell's menus: the Angular app's navigation blueprint
  # (core/configuration/navigation.ts) filtered the way NavigationService
  # filters it — by permission, admin-only and tenant feature — with each
  # path in the current salle (MIGRATION_AUDIT §8).
  class Navigation
    Item = Struct.new(:page, :icon, :label_key, :permission, :admin_only, :feature, :pro, :coming_soon, :query, keyword_init: true)
    Group = Struct.new(:id, :icon, :label_key, :admin_only, :items, keyword_init: true)

    DASHBOARD = Item.new(page: "dashboard", icon: "bi-sun", label_key: "nav.today", permission: "reports")

    # Seven entries, in the order a gym's day runs. "Bookings" is deliberately
    # absent (see navigation.ts).
    GROUPS = [
      Group.new(id: "clients", icon: "bi-people", label_key: "nav.clients", items: [
        Item.new(page: "clients", icon: "bi-people", label_key: "nav.clients", permission: "clients")
      ]),
      # The door: members coming in, whether they booked a class or not.
      Group.new(id: "entries", icon: "bi-qr-code-scan", label_key: "nav.entries", items: [
        Item.new(page: "entries", icon: "bi-qr-code-scan", label_key: "nav.entries", permission: "checkin")
      ]),
      Group.new(id: "planning", icon: "bi-calendar3", label_key: "nav.planning", items: [
        Item.new(page: "calendar", icon: "bi-calendar3", label_key: "nav.planning"),
        Item.new(page: "spaces", icon: "bi-door-open", label_key: "nav.spaces", permission: "spaces", feature: "spaces")
      ]),
      Group.new(id: "subscriptions", icon: "bi-award", label_key: "nav.subscriptions", items: [
        Item.new(page: "contracts", icon: "bi-file-earmark-text", label_key: "nav.subscriptions_active", permission: "contracts"),
        Item.new(page: "catalogue", icon: "bi-award", label_key: "nav.catalogue", permission: "contract_types")
      ]),
      Group.new(id: "finances", icon: "bi-cash-coin", label_key: "nav.payments", items: [
        Item.new(page: "payments", icon: "bi-cash-coin", label_key: "nav.payments", permission: "payments"),
        Item.new(page: "cash", icon: "bi-safe", label_key: "nav.cash", permission: "payments")
      ]),
      Group.new(id: "team", icon: "bi-person-vcard", label_key: "nav.team", admin_only: true, items: [
        Item.new(page: "team", icon: "bi-person-vcard", label_key: "nav.team", permission: "coaches")
      ])
    ].freeze

    SECONDARY = [
      Item.new(page: "salles", icon: "bi-buildings", label_key: "nav.my_salles", admin_only: true, pro: true),
      Item.new(page: "subscription", icon: "bi-stars", label_key: "nav.fitora_subscription", admin_only: true),
      Item.new(page: "updates", icon: "bi-megaphone", label_key: "nav.updates", admin_only: true),
      Item.new(page: "settings", icon: "bi-gear", label_key: "nav.settings", admin_only: true)
    ].freeze

    # MobileBarComponent's three.
    MOBILE = [
      Item.new(page: "dashboard", icon: "bi-sun", label_key: "nav.today", permission: "reports"),
      Item.new(page: "clients", icon: "bi-people", label_key: "nav.clients", permission: "clients"),
      Item.new(page: "payments", icon: "bi-cash-coin", label_key: "payments.collect", permission: "payments", query: { action: "new" })
    ].freeze

    def initialize(user:, bootstrap:, salle:)
      @user = user
      @bootstrap = (bootstrap || {}).with_indifferent_access
      @salle = salle
    end

    def admin?
      @user.admin?
    end

    def dashboard
      visible?(DASHBOARD) ? DASHBOARD : nil
    end

    def groups
      GROUPS.reject { |g| g.admin_only && !admin? }
            .map { |g| g.dup.tap { |copy| copy.items = g.items.select { |i| visible?(i) } } }
            .reject { |g| g.items.empty? }
    end

    # Only an admin's shell lists them (AdminShellComponent#showAdminOnlySections).
    def secondary
      admin? ? SECONDARY.select { |i| visible?(i) } : []
    end

    def mobile
      MOBILE.select { |i| permission?(i.permission) }
    end

    # Every entry the bars can show, for "which page is this" (the mobile
    # title, NavbarComponent#activePageLabel).
    def leaves
      [ dashboard, *groups.flat_map(&:items), *secondary ].compact
    end

    # NavigationService#homePath — where the brand links to.
    def home_page
      dashboard&.page || groups.first&.items&.find { |i| !i.coming_soon }&.page || "settings"
    end

    def path(item_or_page, query = nil)
      page = item_or_page.respond_to?(:page) ? item_or_page.page : item_or_page
      query ||= item_or_page.respond_to?(:query) ? item_or_page.query : nil
      base = "/admin/#{@salle.id}/#{page}"
      query.present? ? "#{base}?#{query.to_query}" : base
    end

    # A group shown as a plain link: it has one entry left (NavbarComponent#soloItem).
    def solo(group)
      group.items.size == 1 ? group.items.first : nil
    end

    # Pro's tools open? True until known, as ConfigurationService#proFeatures.
    def pro_features?
      subscription = @bootstrap[:subscription]
      subscription.nil? ? true : subscription[:pro_features]
    end

    private

    def visible?(item)
      return false if item.admin_only && !admin?
      return false if item.feature && @bootstrap.dig(:features, item.feature) != true
      return true if item.permission.nil?

      permission?(item.permission)
    end

    # AuthService#hasPermission: a superadmin has every key; otherwise the
    # server's list.
    def permission?(key)
      return true if @user.superadmin?

      Array(@bootstrap[:permissions]).include?(key)
    end
  end
end
