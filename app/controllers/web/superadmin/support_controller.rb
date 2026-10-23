module Web
  module Superadmin
    # Every gym's support tickets: the open ones first-hand (?status=all or
    # resolved for the rest), searched by subject, message, gym or author;
    # each on its own page, where it is resolved (SupportRequest.resolve) and
    # its attachments are opened through this session rather than the API's
    # bearer token (B-14).
    class SupportController < BaseController
      include ServesAttachments
      helper_method :support_tel_href

      TABLE = Web::DataTable::Definition.new(
        search: :subject_or_message_or_company_name_or_created_by_first_name_or_created_by_last_name_cont,
        sorts: { created: "created_at", company: "company_name", subject: "subject" },
        default: %w[created desc],
        filters: {
          status: { "open" => { status_eq: SupportTicket.statuses[:open] }, "resolved" => { status_eq: SupportTicket.statuses[:resolved] }, "all" => {} },
          kind: SupportTicket.kinds.to_h { |name, value| [ name, { kind_eq: value } ] }
        },
        defaults: { status: "open" }
      )

      def index
        @table = TABLE.table(params)
        @pagy, @tickets = paginate(@table, SupportTicket.includes(:company, :created_by, :attachments_attachments))
      end

      def show
        ticket = SupportTicket.includes(:company, :created_by, attachments_attachments: :blob).find_by(id: params[:id])
        return redirect_to("/superadmin/support", status: :see_other) if ticket.nil?

        @ticket = ticket_json(ticket)
      end

      # PATCH …/support/:id/resolve — back to the ticket, resolved, with the toast.
      def resolve
        ticket = SupportRequest.resolve(SupportTicket.find(params[:id]), by: current_user)
        flash[:success] = helpers.ngt("superadmin.support.resolved")
        redirect_to "/superadmin/support/#{ticket.id}", status: :see_other
      rescue ActiveRecord::RecordNotFound
        redirect_to "/superadmin/support", status: :see_other
      end

      def attachment
        file = SupportTicket.find(params[:id]).attachments.find(params[:attachment_id])
        redirect_to_attachment(file)
      end

      private

      def ticket_json(ticket)
        JSON.parse(SuperadminSupportTicketSerializer.new(ticket).as_json.to_json).deep_symbolize_keys
      end

      # SuperadminSupportTicketsComponent#telHref: separators out, the
      # leading + kept.
      def support_tel_href(phone)
        "tel:#{phone.to_s.gsub(/[^\d+]/, "")}"
      end
    end
  end
end
