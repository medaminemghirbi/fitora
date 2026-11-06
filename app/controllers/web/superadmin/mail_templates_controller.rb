module Web
  module Superadmin
    # The texts the console's mailing reuses (MailTemplate). Editing or deleting
    # one never touches what was already sent: a mailing keeps its own copy.
    class MailTemplatesController < BaseController
      include MailForm

      before_action :set_template, only: %i[edit update destroy]

      TABLE = Web::DataTable::Definition.new(
        search: :name_or_subject_cont,
        sorts: { name: "name", updated: "updated_at" },
        default: %w[name asc]
      )

      def index
        @table = TABLE.table(params)
        @pagy, @templates = paginate(@table, MailTemplate.all)
      end

      def new
        @template = MailTemplate.new
        @errors = {}
      end

      def create
        @template = MailTemplate.new(template_params)
        save_or_redo(:new)
      end

      def edit
        @errors = {}
      end

      def update
        @template.assign_attributes(template_params)
        save_or_redo(:edit)
      end

      def destroy
        @template.destroy!
        flash[:success] = helpers.ngt("superadmin.mail_templates.deleted")
        head :no_content
      end

      private

      def set_template
        @template = MailTemplate.find_by(id: params[:id])
        return if @template

        request.format.html? ? redirect_to("/superadmin/mail_templates", status: :see_other) : render_refusal("Resource not found", status: :not_found)
      end

      def template_params
        params.fetch(:mail_template, {}).permit(:name, :subject, :body)
      end

      def save_or_redo(form)
        if @template.save
          flash[:success] = helpers.ngt("superadmin.mail_templates.saved")
          return redirect_to("/superadmin/mail_templates", status: :see_other)
        end

        @errors = mail_field_errors(@template)
        render form, status: :unprocessable_content
      end
    end
  end
end
