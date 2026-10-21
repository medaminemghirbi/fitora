module Web
  module Admin
    # "Aujourd'hui" (DashboardComponent): what needs the gym, the figures,
    # the day's sessions (each opening the check-in panel), revenue and the
    # latest payments, and — collapsed — the report export and the latest
    # activity. Read through what /api/v1/admin/dashboard and
    # /api/v1/audit_logs answer, round-tripped through JSON so the page reads
    # the very values the Angular page reads (decimals as strings, times as
    # ISO 8601).
    class DashboardController < BaseController
      before_action -> { require_capability(:reports) }, only: :show
      before_action -> { render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless current_user.admin? }, only: :report

      # GET …/dashboard; ?fragment=1 for the figures alone, as load() redraws
      # them once the check-in panel closes.
      def show
        @data = JSON.parse({ company: CompanySerializer.new(current_company).as_json,
                             stats: Dashboard::Statistics.call(company: current_company, revenue: capability?(:revenue)) }.to_json).deep_symbolize_keys
        @audit_logs = JSON.parse(current_company.audit_logs.includes(:user).recent.limit(5).map { |l| AuditLogSerializer.new(l).as_json }.to_json).map(&:deep_symbolize_keys)
        render partial: "web/admin/dashboard/body", locals: { d: @data, audit_logs: @audit_logs } if params[:fragment].present?
      end

      # GET …/dashboard/report?period_type=month|year&period= — the XLSX
      # workbook, as GET /api/v1/admin/reports/export, under the name the
      # page gives it.
      def report
        period = Reports::Period.parse(period_type: params[:period_type], period: params[:period])
        package = Reports::CompanyWorkbook.call(company: current_company, period: period)
        AuditLog.record!(
          company: current_company, user: current_user, action: "report.exported",
          auditable: current_company, metadata: { period: period.slug }
        )
        send_data package.to_stream.read, filename: "fitora-rapport-#{period.slug}.xlsx",
                                          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
      rescue Reports::Period::InvalidPeriod => e
        render json: { error: e.message }, status: :unprocessable_content
      end
    end
  end
end
