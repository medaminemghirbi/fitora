module Web
  # The superadmin console's small decisions, as its Angular components make them.
  module SuperadminHelper
    # SuperadminOverviewComponent#money: cents as a readable amount, in the
    # browser's own language (toLocaleString(undefined, …), B-03), at most
    # two decimals.
    def superadmin_money(cents)
      Web::NumberFormat.locale_string(cents.to_i / 100.0, locale: locale_code == "ar" ? "ar-TN" : locale_code, max_fraction: 2)
    end

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

    # SuperadminCompanyDetailComponent#attention: the one thing the page is
    # for, when there is one — an open, paid-up gym gets no banner.
    def superadmin_attention(company)
      sub = company[:subscription] || {}
      unless sub[:active]
        return "suspended" if sub[:lock_reason] != "unpaid"

        # Closed because the free days ran out, not because a payment lapsed.
        return sub[:trial] ? "trial_over" : "unpaid"
      end
      return nil if sub[:current_period_paid]

      # Nothing was ever invoiced, so there is no period to count down from.
      sub[:paid_through].nil? ? "never" : "due"
    end

    # #since: the gym's first day, or its first invoice if an import
    # predates it.
    def superadmin_since(company, invoices)
      starts = invoices.map { |i| Web::PaymentLedger.utc_date(i[:period_start]).to_time(:utc) }
      starts << Time.zone.parse(company[:created_at]) if company[:created_at]
      starts.min
    end

    # "Formule — tagline" in the plan select (PLAN_KEYS).
    def superadmin_plan_keys
      %w[starter pro]
    end
  end
end
