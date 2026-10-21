module Web
  module Desk
    # The search at the top of every desk screen (DeskShellComponent
    # #onSearch): the first six members GET /api/v1/clients?search= lists,
    # drawn as the results panel — refused as that endpoint refuses it
    # (`clients`), which the Angular shell shows as no results.
    class ClientsController < BaseController
      PER_PAGE = 6

      def index
        return render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:clients)

        rows = Clients::ListQuery.new(current_company, search: params[:search].to_s).serialized_page(1, PER_PAGE)
        render partial: "web/desk/clients/results", locals: { clients: JSON.parse(rows.to_json).map(&:deep_symbolize_keys), term: params[:term].to_s }
      end
    end
  end
end
