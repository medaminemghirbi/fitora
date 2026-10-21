module Web
  module Admin
    # Writing to Fitora (AdminSupportComponent): the form, and the gym's own
    # history of what it has asked. Tickets are opened by SupportRequest, as
    # POST /api/v1/support_tickets opens them.
    class SupportController < BaseController
      before_action :require_admin

      def index
        @tickets = tickets
      end

      # POST …/support — the page's fetch; answers with the history and a toast.
      def create
        ticket = SupportRequest.open(company: current_company, user: current_user,
                                     subject: params[:subject].to_s.strip, message: params[:message].to_s.strip,
                                     attachments: params[:attachments])
        if ticket.persisted?
          render turbo_stream: [
            turbo_stream.replace("support-history", partial: "web/admin/support/history", locals: { tickets: tickets }),
            turbo_stream.append("toasts", partial: "web/shared/toast", locals: { kind: "success", message: helpers.ngt("modules_page.contact.sent") })
          ]
        else
          # The API's English message, as the Angular page toasts it (K-04).
          message = I18n.with_locale(:en) { ticket.errors.full_messages.first }
          render turbo_stream: turbo_stream.append("toasts", partial: "web/shared/toast", locals: { kind: "error", message: message }),
                 status: :unprocessable_content
        end
      end

      # GET …/support/:id/attachments/:attachment_id — this salle's own files
      # only. The Angular page links the API's address, which a plain link
      # cannot open (it needs the bearer token): B-06.
      def attachment
        ticket = current_company.support_tickets.find(params[:id])
        file = ticket.attachments.find(params[:attachment_id])
        send_data file.download, filename: file.filename.to_s, type: file.content_type, disposition: "inline"
      end

      private

      def tickets
        current_company.support_tickets.recent.includes(attachments_attachments: :blob).map { |t| SupportTicketSerializer.new(t).as_json }
      end
    end
  end
end
