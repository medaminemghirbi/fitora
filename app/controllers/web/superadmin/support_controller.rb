module Web
  module Superadmin
    # Every gym's support tickets (SuperadminSupportTicketsComponent): the
    # open ones, or all (?status=all, M-05), as GET
    # /api/v1/superadmin/support_tickets lists them (its first page), each
    # opening in a dialog; resolving one (SupportRequest.resolve); and its
    # attachments, through this session rather than the API's bearer token
    # (B-14). ?fragment=1 is the page without the shell, as the filter
    # redraws it.
    class SupportController < BaseController
      helper_method :support_tel_href

      def index
        @filter = params[:status] == "all" ? "all" : "open"
        scope = SupportTicket.includes(:company, :created_by, attachments_attachments: :blob).recent
        scope = scope.where(status: :open) if @filter == "open"
        rows, = page_meta(scope)
        @tickets = rows.map { |t| ticket_json(t) }
        render :index, layout: false if params[:fragment].present?
      end

      # PATCH …/support/:id/resolve — the ticket's row and dialog, redrawn.
      def resolve
        ticket = SupportRequest.resolve(SupportTicket.find(params[:id]), by: current_user)
        t = ticket_json(ticket)
        render json: {
          row: render_to_string(partial: "web/superadmin/support/row", formats: [ :html ], locals: { t: t }),
          detail: render_to_string(partial: "web/superadmin/support/detail", formats: [ :html ], locals: { t: t })
        }
      rescue ActiveRecord::RecordNotFound
        render_refusal("Resource not found", status: :not_found)
      end

      def attachment
        file = SupportTicket.find(params[:id]).attachments.find(params[:attachment_id])
        send_data file.download, filename: file.filename.to_s, type: file.content_type, disposition: "inline"
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
