module Web
  module Admin
    # The door (/admin/<salle>/entries): a member's card scanned, its number
    # typed or a name searched; the verdict Visit.verdict_for gives — green,
    # amber or red, and why — and the visit written down, forced or not. The
    # day's visits sit beside it, any earlier day's on request (?date=).
    # Behind `checkin`, as pointing people into a class is.
    class EntriesController < BaseController
      LOOKUP_LIMIT = 6
      # The undo is for a wrong pick at the desk, not for rewriting history.
      UNDO_WITHIN = 1.hour

      before_action -> { require_capability(:checkin) }, only: :index
      before_action :refuse_without_checkin, except: :index
      before_action :set_client, only: %i[check create]

      rescue_from ApplicationRecord::Refused, with: ->(refusal) { render json: { error: refusal_message(refusal) }, status: :unprocessable_content }

      def index
        @date = requested_date
        @visits = current_company.visits.on_day(@date).newest_first
                                 .includes(:checked_in_by, client: [], contract: :contract_type).to_a
        @memberships = memberships_of(@visits.map(&:client_id))
        @member = current_company.clients.find_by(id: params[:member]) if params[:member].present?
        render partial: "web/admin/entries/day", locals: { date: @date, visits: @visits, memberships: @memberships } if params[:fragment] == "day"
      end

      # GET …/entries/lookup?q= — a card number goes straight to its
      # member's verdict; anything else lists who it matches.
      def lookup
        query = params[:q].to_s.strip
        membership = current_company.memberships.find_by_card(query)
        return render_verdict(membership.client) if membership

        clients = query.length < 2 ? [] : current_company.clients.search(query).order(:first_name, :last_name).limit(LOOKUP_LIMIT).to_a
        render partial: "web/admin/entries/matches",
               locals: { clients: clients, memberships: memberships_of(clients.map(&:id)), query: query }
      end

      # GET …/entries/check/:client_id — one member's verdict.
      def check
        render_verdict(@client)
      end

      # POST …/entries — let them in; `force` past a red verdict.
      def create
        visit = Visit.admit!(client: @client, company: current_company, by: current_user,
                             force: ActiveModel::Type::Boolean.new.cast(params[:force]) || false)
        render json: { id: visit.id, forced: visit.forced, consumed_session: visit.consumed_session }, status: :created
      end

      # DELETE …/entries/:id — a visit recorded by mistake, shortly after.
      def destroy
        visit = current_company.visits.find_by(id: params[:id])
        return render(json: { error: page_words("entries.errors.not_found") }, status: :not_found) if visit.nil?
        if visit.checked_in_at < UNDO_WITHIN.ago
          return render(json: { error: page_words("entries.errors.too_late_to_undo") }, status: :unprocessable_content)
        end

        visit.undo!
        AuditLog.record!(company: current_company, user: current_user, action: "visit.undone", auditable: visit,
                         metadata: { name: visit.client.full_name })
        head :no_content
      end

      private

      def render_verdict(client)
        render partial: "web/admin/entries/verdict",
               locals: { client: client, membership: client.membership_for(current_company),
                         verdict: Visit.verdict_for(client, current_company) }
      end

      def set_client
        @client = current_company.clients.find_by(id: params[:client_id])
        render(json: { error: page_words("entries.errors.not_found") }, status: :not_found) if @client.nil?
      end

      def refuse_without_checkin
        render(json: { error: "You are not allowed to perform this action" }, status: :forbidden) unless capability?(:checkin)
      end

      # Today, or the day asked for — never one still to come.
      def requested_date
        date = params[:date].present? ? Date.parse(params[:date].to_s) : Date.current
        [ date, Date.current ].min
      rescue Date::Error
        Date.current
      end

      # This gym's memberships of these members, photos loaded.
      def memberships_of(client_ids)
        current_company.memberships.where(client_id: client_ids.uniq).with_attached_photo.index_by(&:client_id)
      end
    end
  end
end
