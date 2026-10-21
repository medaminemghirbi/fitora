module Web
  # The desk shell's small decisions, as DeskShellComponent makes them.
  module DeskHelper
    # DeskShellComponent#navItems: the desk's two pages, then the admin
    # shell's pages a desk works from — crossing to them is a full page load
    # (through the hand-off while the admin shell is still Angular's).
    def desk_nav
      [
        [ desk_path("dashboard"), "bi-house", "desk.nav.today" ],
        [ desk_path("checkin"), "bi-check2-square", "desk.nav.checkin" ],
        [ served_path("/admin/#{salle.id}/clients"), "bi-people", "desk.nav.members" ],
        [ served_path("/admin/#{salle.id}/calendar"), "bi-calendar3", "desk.nav.schedule" ],
        [ served_path("/admin/#{salle.id}/contracts"), "bi-award", "desk.nav.subscriptions" ],
        [ served_path("/admin/#{salle.id}/payments"), "bi-cash-coin", "desk.nav.payments" ]
      ].map { |href, icon, label_key| { href: href, icon: icon, label_key: label_key, active: desk_link_active?(href) } }
    end

    # RouterLinkActive: the link's path is a segment-wise prefix of the page's.
    def desk_link_active?(href)
      wanted = href.split("?").first.split("/").reject(&:empty?)
      request.path.split("/").reject(&:empty?).first(wanted.size) == wanted
    end

    # DeskDashboardComponent#daysUntil: days until a membership lapses,
    # rounded up — negative once it has. `new Date("2026-10-20")` reads a
    # bare date as midnight UTC, and so does this.
    def desk_days_until(iso_date)
      expires = iso_date.to_s.match?(/\A\d{4}-\d\d-\d\d\z/) ? Time.utc(*iso_date.split("-").map(&:to_i)) : Time.zone.parse(iso_date)
      ((expires - Time.current) / 1.day).ceil
    end
  end
end
