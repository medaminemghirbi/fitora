module Web
  module Admin
    # The command palette's remote search (CommandPaletteComponent#runRemote):
    # the first five members, contracts and payments a term finds, as
    # GET /api/v1/clients?search=, /contracts?q= and /payments?q= list them
    # on their first page — one request here for the palette's three. Each
    # comes with where choosing it goes. An admin's only, as in Angular.
    class PaletteController < BaseController
      LIMIT = 5

      before_action :require_admin_json

      def search
        term = params[:q].to_s.strip
        render json: { clients: clients(term), contracts: contracts(term), payments: payments(term) }
      end

      private

      def require_admin_json
        render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless current_user.admin?
      end

      def clients(term)
        Clients::ListQuery.new(current_company, { search: term }).scope.limit(LIMIT).map do |c|
          # c.phone ?? c.email: an empty phone is still the phone.
          { id: "cli:#{c.id}", label: c.full_name, sub: c.phone.nil? ? c.email : c.phone, icon: "bi-person", url: admin_page_path("clients/#{c.id}") }
        end
      end

      def contracts(term)
        Contracts::ListQuery.new(current_company, { q: term }, revenue: false).scope.limit(LIMIT).map do |m|
          { id: "ctr:#{m.id}", label: m.client.full_name, sub: m.contract_type.name, icon: "bi-file-earmark-text", url: admin_page_path("clients/#{m.client.id}") }
        end
      end

      # The amount as the API's JSON writes it ("120.0"), then the currency.
      def payments(term)
        Payments::ListQuery.new(current_company, { q: term }).scope.includes(:client).limit(LIMIT).map do |p|
          { id: "pay:#{p.id}", label: p.client.full_name, sub: "#{p.amount.as_json} #{p.currency}", icon: "bi-credit-card", url: admin_page_path("payments", q: term) }
        end
      end
    end
  end
end
