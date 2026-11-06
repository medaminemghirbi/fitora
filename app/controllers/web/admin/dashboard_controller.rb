module Web
  module Admin
    # "Aujourd'hui" (DashboardComponent): what needs the gym, the figures,
    # the day's sessions (each opening the check-in panel), revenue and the
    # latest payments, and — collapsed — the latest activity. Read through what /api/v1/admin/dashboard and
    # /api/v1/audit_logs answer, round-tripped through JSON so the page reads
    # the very values the Angular page reads (decimals as strings, times as
    # ISO 8601).
    class DashboardController < BaseController
      before_action -> { require_capability(:reports) }, only: :show

      # GET …/dashboard; ?fragment=1 for the figures alone, as load() redraws
      # them once the check-in panel closes.
      def show
        @data = JSON.parse({ company: CompanySerializer.new(current_company).as_json,
                             stats: Dashboard::Statistics.call(company: current_company, revenue: capability?(:revenue)) }.to_json).deep_symbolize_keys
        @audit_logs = JSON.parse(current_company.audit_logs.includes(:user).recent.limit(5).map { |l| AuditLogSerializer.new(l).as_json }.to_json).map(&:deep_symbolize_keys)
        render partial: "web/admin/dashboard/body", locals: { d: @data, audit_logs: @audit_logs } if params[:fragment].present?
      end
    end
  end
end
