module Web
  module Superadmin
    # The console's mailing: what was sent and how it went, and writing a new
    # one — a template or free text, the admin accounts it goes to, each getting
    # their own values for its variables (AdminMailing).
    class MailingsController < BaseController
      include MailForm

      TABLE = Web::DataTable::Definition.new(
        search: :subject_or_body_cont,
        sorts: { subject: "subject", created: "created_at" },
        default: %w[created desc]
      )

      def index
        @table = TABLE.table(params)
        @pagy, @mailings = paginate(@table, Mailing.includes(:sent_by, :recipients))
      end

      # GET …/new?template_id=&admin_id= — a template already picked, an account
      # already ticked: where the templates and a gym's page lead.
      def new
        template = MailTemplate.find_by(id: params[:template_id]) if params[:template_id].present?
        @chosen_template_id = template&.id
        @mailing = Mailing.new(subject: template&.subject, body: template&.body)
        @selected_ids = Array(params[:admin_id]).map(&:to_s)
        @errors = {}
        load_form
      end

      def create
        @selected_ids = Array(params[:recipient_ids]).map(&:to_s)
        @chosen_template_id = params[:template_id].presence
        @mailing = AdminMailing.start(params.fetch(:mailing, {}).permit(:subject, :body), @selected_ids, by: current_user)
        if @mailing.persisted?
          flash[:success] = helpers.ngt("superadmin.mailing.started", count: @mailing.recipients.size)
          return redirect_to("/superadmin/mailings/#{@mailing.id}", status: :see_other)
        end

        @errors = mail_field_errors(@mailing)
        load_form
        render :new, status: :unprocessable_content
      end

      def show
        @mailing = Mailing.includes(:sent_by, recipients: { user: :companies }).find_by(id: params[:id])
        redirect_to("/superadmin/mailings", status: :see_other) if @mailing.nil?
      end

      private

      def load_form
        @templates = MailTemplate.order(:name)
        @admins = User.admin.active.includes(:companies).order(:first_name, :last_name)
      end
    end
  end
end
