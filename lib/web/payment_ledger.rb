module Web
  # payment-ledger.ts: every month of a year, and the invoice covering it —
  # the grid the superadmin reads a gym's payments from. `invoices` are
  # InvoiceSerializer rows (dates as "YYYY-MM-DD", read as midnight UTC as
  # `new Date(…)` reads them); "today" is the platform's clock, which the
  # Angular page reads from the browser's.
  module PaymentLedger
    # Written in French whatever the page's language, as the Angular util has them.
    MONTHS = %w[Jan Fév Mar Avr Mai Jun Jul Aoû Sep Oct Nov Déc].freeze

    Cell = Struct.new(:label, :state, :invoice, keyword_init: true)

    # The years the invoices touch, and this one.
    def self.years(invoices, today: Time.current)
      years = Set[today.year]
      invoices.each { |i| (utc_date(i[:period_start]).year..utc_date(i[:period_end]).year).each { |y| years << y } }
      years.sort
    end

    # `since`: the gym's first day (its creation, or its first invoice if an
    # import predates it); months wholly before it are "before".
    def self.for(year, invoices, today: Time.current, since: nil)
      start = since && since.utc.to_date
      MONTHS.each_with_index.map do |label, month|
        first = Date.new(year, month + 1, 1)
        next Cell.new(label: label, state: "before") if start && first.next_month <= start

        day = start && start > first ? start : first
        covering = invoices.find { |i| utc_date(i[:period_start]) <= day && utc_date(i[:period_end]) >= day }
        next Cell.new(label: label, state: covering[:trial] ? "trial" : "paid", invoice: covering) if covering

        future = year > today.year || (year == today.year && month + 1 > today.month)
        next Cell.new(label: label, state: "future") if future

        Cell.new(label: label, state: year == today.year && month + 1 == today.month ? "current" : "missed")
      end
    end

    def self.utc_date(value)
      Date.iso8601(value.to_s[0, 10])
    end
  end
end
