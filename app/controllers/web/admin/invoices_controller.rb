module Web
  module Admin
    # One of the account's invoices as a PDF — paid, or the bill still to pay
    # — as GET /api/v1/invoices/:id sends it. The admin's alone, and open to
    # a locked account (TenantRules: the way out is settling).
    class InvoicesController < BaseController
      self.lock_area = :invoices

      before_action :require_admin

      def show
        invoice = (current_company.subscription&.invoices || Invoice.none).find_by(id: params[:id])
        return head(:not_found) if invoice.nil?

        send_data Receipts::SubscriptionInvoicePdf.call(invoice: invoice),
                  filename: "#{invoice.number}.pdf", type: "application/pdf", disposition: "attachment"
      end
    end
  end
end
