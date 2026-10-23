module Clients
  # A gym's member list: the search box, the status pills and their counts,
  # the advanced filters, the sort — what GET /api/v1/clients answers and
  # what the web UI's members page shows, from one definition
  # (MIGRATION_AUDIT §3.2). Moved here unchanged from
  # Api::V1::ClientsController.
  #
  # Every filter is optional and they compose: the counts are computed AFTER
  # the narrowing, so the status pills say how many rows each status would
  # return for the filters already set.
  class ListQuery
    STATUS_FILTERS = %w[active inactive contract_active contract_expired no_contract].freeze

    # Sort key → the columns it orders on. Anything else falls back to name.
    SORTS = {
      "name" => %w[clients.first_name clients.last_name],
      "joined" => %w[memberships.joined_at],
      "created" => %w[clients.created_at]
    }.freeze

    FILTERS = %i[search status contract_type_id activity_id gender joined_from joined_to sort direction].freeze

    # `params`: a Hash or ActionController::Parameters; only FILTERS are read.
    def initialize(company, params)
      @company = company
      params = params.slice(*FILTERS).permit(*FILTERS) if params.respond_to?(:permit)
      @params = params.to_h.with_indifferent_access.slice(*FILTERS)
    end

    attr_reader :params

    # The rows, filtered, status-scoped and ordered (not paginated).
    def scope
      status_scope(narrowed, params[:status]).order(Arel.sql(order_clause))
    end

    # What each status would return for the CURRENT search and filters — the
    # pills show these next to their labels, so they follow the search box
    # and not the status already picked.
    def counts
      STATUS_FILTERS.index_with { |status| status_scope(narrowed, status).count }
                    .merge("all" => narrowed.count)
    end

    # One page of rows as ClientSerializer says them, with what each row
    # shows beside the member (last visit, membership, current contract).
    def serialized_page(page, per_page)
      rows = scope.limit(per_page).offset((page - 1) * per_page).to_a
      visits = last_visits_for(rows)
      context = ClientSerializer.page_context(rows, company)
      rows.map do |c|
        ClientSerializer.new(
          c, company: company, last_visit_at: visits[c.id],
          membership: context[:memberships][c.id], current_contract: context[:current_contracts][c.id]
        ).as_json
      end
    end

    # When each member last turned up, for the whole page in one query.
    # Asking per member would be twenty aggregates for twenty rows — the kind
    # of N+1 that only shows up once a gym has real traffic.
    def last_visits_for(page)
      return {} if page.empty?

      Booking.confirmed
             .joins(:session)
             .where(client_id: page.map(&:id), sessions: { company_id: company.id })
             .group(:client_id)
             .maximum("sessions.starts_at")
    end

    # The whole filtered list, for the admin's export.
    def csv
      joined = company.memberships.pluck(:client_id, :joined_at, :active).to_h { |id, at, on| [ id, [ at, on ] ] }
      CsvSafe.generate do |csv|
        csv << [ "First name", "Last name", "Email", "Phone", "Active", "Joined at" ]
        scope.find_each do |c|
          at, on = joined[c.id]
          csv << [ c.first_name, c.last_name, c.email, c.phone, on, at ]
        end
      end
    end

    private

    attr_reader :company

    def narrowed
      @narrowed ||= narrow(company.clients.search(params[:search]))
    end

    # The advanced filters, each a no-op when its parameter is absent.
    def narrow(scope)
      scope = scope.where(id: plan_holders.select(:client_id)) if params[:contract_type_id].present?
      scope = scope.where(id: activity_holders.select(:client_id)) if params[:activity_id].present?
      scope = scope.where(memberships: { gender: params[:gender] }) if params[:gender].present?

      from = parse_date(params[:joined_from])
      to = parse_date(params[:joined_to])
      scope = scope.where(memberships: { joined_at: from.beginning_of_day.. }) if from
      scope = scope.where(memberships: { joined_at: ..to.end_of_day }) if to
      scope
    end

    def plan_holders
      company_contracts.where(contract_type_id: params[:contract_type_id])
    end

    # An all-access contract (activity_id NULL) covers every activity its
    # plan is priced for, and a pack contract every activity in its pack,
    # so filtering on an activity has to find those too — see
    # Contract#covers_activity?, which is the same rule.
    def activity_holders
      id = params[:activity_id]
      all_access_plans = company.contract_types
                                .joins(:contract_type_activities)
                                .where(contract_type_activities: { activity_id: id })
      packs_with_it = PackActivity.where(activity_id: id).select(:pack_id)

      company_contracts.where(activity_id: id)
                       .or(company_contracts.where(activity_id: nil, pack_id: nil, contract_type_id: all_access_plans))
                       .or(company_contracts.where(pack_id: packs_with_it))
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error, TypeError
      nil
    end

    # A whitelist, because both halves come off a query string. "name" is two
    # columns, so the direction has to be spelled onto each of them.
    def order_clause
      direction = params[:direction] == "desc" ? "DESC" : "ASC"
      columns = SORTS.fetch(params[:sort], SORTS.fetch("name"))
      columns.map { |column| "#{column} #{direction}" }.join(", ")
    end

    # "Active" here means active AT THIS GYM (the membership), and every
    # contract test is restricted to this gym's contracts — a person who is
    # subscribed elsewhere must not read as subscribed here.
    def status_scope(scope, status)
      case status
      when "active" then scope.where(memberships: { active: true })
      when "inactive" then scope.where(memberships: { active: false })
      when "contract_active" then scope.where(id: company_contracts.currently_active.select(:client_id))
      # Lapsed and not followed by anything running: someone to bring back.
      when "contract_expired"
        scope.where(id: company_contracts.lapsed.select(:client_id))
             .where.not(id: company_contracts.currently_active.select(:client_id))
      when "no_contract" then scope.where.not(id: company_contracts.select(:client_id))
      else scope
      end
    end

    def company_contracts
      company.contracts
    end
  end
end
