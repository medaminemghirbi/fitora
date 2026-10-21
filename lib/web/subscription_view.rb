module Web
  # SubscriptionComponent's computed values over /api/v1/subscription's
  # payload (SubscriptionStatusSerializer), for the server-rendered page.
  # "Today" is the gym's local day (B-04); the period's progress is measured
  # from local midnights, as the component measures it.
  class SubscriptionView
    PRO_FEATURES = [
      [ "multi_salle", "bi-buildings", :multi_salle ],
      [ "member_app", "bi-phone", :member_app ],
      [ "updates", "bi-arrow-repeat", :member_app ],
      [ "roles", "bi-shield-lock", :pro_features ],
      [ "branding", "bi-palette", :pro_features ],
      [ "data_exchange", "bi-arrow-down-up", :pro_features ],
      [ "print", "bi-printer", :pro_features ]
    ].freeze

    attr_reader :info

    def initialize(info, now: Time.zone.now)
      @info = info.deep_symbolize_keys
      @now = now
    end

    def sub = info[:subscription] || {}
    def access_open? = sub[:active] || false
    def paid_through = sub[:paid_through]
    def currency = info[:currency] || "TND"
    def arrears = (info[:arrears_cents] || 0) / 100.0
    def on_trial? = sub[:trial] || false
    def trial_days_left = sub[:trial_days_left] || 0
    def trial_running? = on_trial? && access_open? && trial_days_left.positive?
    def trial_over? = on_trial? && !trial_running?
    def yearly? = sub[:billing_period] == "yearly"

    def access_state
      return "trial" if trial_running?
      return "closed" if trial_over? || !access_open?

      sub[:current_period_paid] ? "open" : "due"
    end

    def access_label
      return "subscription.trial_running" if trial_running?
      return "subscription.tier_trial_over" if trial_over?

      "subscription.pill_#{access_state}"
    end

    def current_plan_name
      return "subscription.tier_trial" if trial_running?
      return "subscription.tier_trial_over" if trial_over?

      sub[:plan] ? "subscription.plan_#{sub[:plan]}" : "subscription.tier_trial"
    end

    def current_plan_tagline
      return "subscription.tier_trial_for" if trial_running?
      return "subscription.trial_over_sub" if trial_over?

      "#{current_plan_name}_for"
    end

    def current_price
      (yearly? ? info[:annual_subscription_cents] : info[:monthly_subscription_cents]).to_i / 100.0
    end

    # The invoice today falls in (or the newest), and how far through it
    # we are, in whole percent.
    def period
      today = @now.to_date
      invoices = info[:invoices] || []
      current = invoices.find { |i| i[:period_start].to_date <= today && today <= i[:period_end].to_date } || invoices.first
      return nil if current.nil?

      start = current[:period_start].to_date.in_time_zone
      finish = current[:period_end].to_date.in_time_zone + 1.day
      done = ((@now - start) / (finish - start)).clamp(0, 1)
      { start: current[:period_start].to_date, end: current[:period_end].to_date, percent: js_round(done * 100) }
    end

    def renews_in
      return nil if paid_through.nil?

      (paid_through.to_date - @now.to_date).to_i + 1
    end

    def usage
      [ [ "companies", "bi-building", info[:companies_count] ], [ "staff", "bi-person-badge", info[:staff_used] ], [ "clients", "bi-people", info[:clients_used] ] ]
    end

    def pro_features
      PRO_FEATURES.map { |key, icon, flag| { key: key, icon: icon, held: sub[flag] || false } }
    end

    def included
      (info[:included_modules] || []).map { |key| [ key, "modules.#{key}.name" ] } + [ [ "shared_team", "subscription.extra_shared_team" ] ]
    end

    # The plans, for the period the account is billed on.
    def billing_period
      yearly? ? "yearly" : "monthly"
    end

    def plans
      (info[:plans] || []).map do |plan|
        { key: plan[:key], name_key: "subscription.plan_#{plan[:key]}", monthly: plan[:monthly_cents] / 100.0, yearly: plan[:annual_cents] / 100.0,
          current: !on_trial? && plan[:key] == sub[:plan] }
      end
    end

    private

    # Math.round: halves round up, as JavaScript does.
    def js_round(value)
      (value + 0.5).floor
    end
  end
end
