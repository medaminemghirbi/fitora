module Web
  # DashboardComponent's small formatters, as it formats.
  module DashboardHelper
    # #money: the amount as Number#toLocaleString writes it in the page's
    # language, then the currency's symbol.
    def dashboard_money(amount, symbol)
      "#{Web::NumberFormat.locale_string(amount.to_f)} #{symbol}".strip
    end

    # #shortAmount, a gridline's label: thousands as "6k".
    def dashboard_short_amount(value)
      return "#{Web::LineChart.num((value / 100.0 + 0.5).floor / 10.0)}k" if value >= 1000

      ((value + 0.5).floor).to_s
    end

    # #auditLabel: the action's translation, or the action made readable.
    def dashboard_audit_label(action)
      key = "audit.#{action}"
      translated = ngt(key)
      return translated unless translated == key

      action.tr("._", "  ").sub(/\A./, &:upcase)
    end

    # #fillPct: how full a session is, out of 100.
    def dashboard_fill_pct(item)
      item[:capacity].to_i.positive? ? [ 100, (item[:confirmed_count].to_f / item[:capacity]) * 100 ].min : 0
    end
  end
end
