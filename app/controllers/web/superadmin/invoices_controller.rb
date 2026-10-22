module Web
  module Superadmin
    # Every invoice Fitora has issued, across every account: what was paid,
    # what is waiting to be, and the free trials — the platform's own ledger,
    # never a gym's takings. Read-only: an invoice is recorded or taken back
    # from its gym's page (SuperadminActions#issue_invoice, #void_invoice),
    # where its audit trail and the admin's notification go with it.
    class InvoicesController < BaseController
      # By number, or by the account: its admin's name and e-mail, its
      # salles' names (a has_many, hence distinct).
      TABLE = Web::DataTable::Definition.new(
        search: :number_or_subscription_admin_first_name_or_subscription_admin_last_name_or_subscription_admin_email_or_subscription_admin_companies_name_cont,
        sorts: { number: "number", issued: "issued_at", amount: "amount_cents", period: "period_start" },
        default: %w[issued desc],
        filters: {
          status: { "paid" => { paid_at_not_null: true, trial_eq: false }, "due" => { paid_at_null: true }, "trial" => { trial_eq: true } },
          plan: { "starter" => { plan_eq: "starter" }, "pro" => { plan_eq: "pro" } },
          period: Subscription::BILLING_PERIODS.to_h { |name, value| [ name.to_s, { billing_period_eq: value, trial_eq: false } ] }
        },
        distinct: true
      )

      # GET /superadmin/invoices?search=&status=&plan=&period=&sort=&dir=&page=&limit=
      def index
        @table = TABLE.table(params)
        @pagy, @invoices = paginate(@table, Invoice.includes(:issued_by, subscription: { admin: :companies }))
      end
    end
  end
end
