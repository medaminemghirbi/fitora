module Web
  # The superadmin console's small decisions, as its Angular components make them.
  module SuperadminHelper
    # SuperadminOverviewComponent#signupTrend: this month's sign-ups against
    # last month's, in whole percent; nil with nothing to compare against.
    def superadmin_signup_trend(companies)
      return nil if companies[:new_last_month].zero?

      ((companies[:new_this_month] - companies[:new_last_month]) * 100.0 / companies[:new_last_month]).round
    end

    # #activeShare: the share of gyms that ran a session in 30 days.
    def superadmin_active_share(metrics)
      total = metrics.dig(:companies, :total)
      total.zero? ? nil : (metrics.dig(:activity, :companies_with_activity) * 100.0 / total).round
    end

    # Where an account stands, as a badge's status and its words: suspended,
    # the address to confirm, the first sign-in to make, or done.
    def superadmin_activation(state)
      [ { "active" => "active", "suspended" => "failed" }.fetch(state.to_s, "pending"), ngt("superadmin.activation.#{state}") ]
    end

    # ---- the console's frame and tables (Web::DataTable) -------------------

    # The side menu, Administrate's list of dashboards: grouped, the page's
    # own marked (a gym's page is under the gyms), the open tickets counted.
    def superadmin_nav
      here = request.path
      item = lambda do |page, icon, label, badge = nil|
        path = "/superadmin/#{page}"
        { path: path, icon: icon, label: label, badge: badge, active: here == path || here.start_with?("#{path}/") }
      end
      [
        { label: ngt("superadmin.console.section_platform"), items: [
          item.call("overview", "bi-speedometer2", ngt("superadmin.overview.nav"))
        ] },
        { label: ngt("superadmin.console.section_accounts"), items: [
          item.call("companies", "bi-buildings", ngt("superadmin.companies"))
        ] },
        { label: ngt("superadmin.console.section_service"), items: [
          item.call("support", "bi-headset", ngt("superadmin.support_nav"), SupportTicket.open.count),
          item.call("updates", "bi-megaphone", ngt("superadmin.updates_nav"))
        ] },
        { label: ngt("superadmin.console.section_communication"), items: [
          item.call("mailings", "bi-envelope", ngt("superadmin.mailing.nav")),
          item.call("mail_templates", "bi-file-earmark-text", ngt("superadmin.mail_templates.nav"))
        ] },
        { label: ngt("superadmin.console.section_settings"), items: [
          item.call("identity", "bi-card-heading", ngt("superadmin.identity.nav"))
        ] }
      ]
    end

    # Where the page sits, for the top bar: each crumb [label, path], the
    # page itself a label alone.
    def superadmin_crumbs(*crumbs)
      items = crumbs.map do |label, path|
        path ? link_to(label, path, class: "sa-crumb") : tag.span(label, class: "sa-crumb is-current", aria: { current: "page" })
      end
      content_for :superadmin_crumbs, safe_join(items, tag.i(class: "bi bi-chevron-right sa-crumb-sep", aria: { hidden: true }))
    end

    # A sortable column's header: a link that sorts by it (the other way
    # round once it does), its arrow saying which way, aria-sort saying so to
    # a screen reader. It is inside the table's frame, so only the table is
    # redrawn.
    def superadmin_sort_th(table, key, label, base, css: nil)
      sorted = table.sorted_by?(key)
      icon = !sorted ? "bi-arrow-down-up" : (table.dir == "asc" ? "bi-sort-up" : "bi-sort-down")
      aria_sort = (table.dir == "asc" ? "ascending" : "descending") if sorted
      tag.th(class: [ css, ("is-sorted" if sorted) ], scope: "col", aria: { sort: aria_sort }) do
        link_to(table.path(base, sort: key, dir: table.next_dir(key)), class: "fx-th-sort") do
          safe_join([ label, tag.i(class: "bi #{icon}", aria: { hidden: true }) ], " ")
        end
      end
    end

    # The pages the footer links: every one up to seven, else the first, the
    # last, the current one's neighbours and a gap either side as needed.
    def superadmin_page_series(pagy)
      last = pagy.last
      return (1..last).to_a if last <= 7

      from = (pagy.page - 1).clamp(2, last - 3)
      [ 1, (:gap if from > 2), *(from..from + 2), (:gap if from + 2 < last - 1), last ].compact
    end
  end
end
