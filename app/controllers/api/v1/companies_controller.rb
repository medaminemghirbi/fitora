module Api
  module V1
    class CompaniesController < BaseController
      # A staff login posted to several salles lists and switches between
      # them too; everything else here is the admin's.
      before_action :require_admin!, except: [ :index, :switch ]
      before_action :set_workplace, only: [ :switch ]
      before_action :set_owned_company, only: [ :update_moderators ]
      # Several salles — the "Mes salles" page, its moderators, and moving
      # between salles — are Pro's. Starter and the free trial run one.
      before_action :require_pro!, only: [ :network, :update_moderators, :switch ]

      # GET /api/v1/company — the admin's currently ACTIVE company (see
      # #switch). Everything else in the API (current_company) follows
      # whichever one this is.
      def show
        render json: { company: CompanySerializer.new(current_company).as_json }
      end

      # GET /api/v1/companies — every salle this login can switch between
      # (User#workplaces), for the navbar switcher. Order is oldest-first
      # (predictable, matches signup order) rather than alphabetical, which
      # would reorder itself as they rename one.
      def index
        companies = current_user.workplaces.order(:created_at)
        render json: {
          companies: companies.map { |c| CompanySummarySerializer.new(c, active: c.id == current_company&.id).as_json }
        }
      end

      # GET /api/v1/companies/network — the admin's "Mes salles" page: every
      # salle with what it holds, and every moderator with where they work.
      def network
        render json: network_json
      end

      # POST /api/v1/companies — the admin's first salle, or another under
      # the same login: on a paid Pro account as many as they like, at one
      # price however many salles it covers; Starter runs one. Becomes the
      # active company immediately.
      def create
        unless current_user.may_open_salle?
          return render json: {
            error: "multi_salle_not_included",
            message: "Several salles come with Fitora Pro."
          }, status: :forbidden
        end

        company = Company.open!(admin: current_user, attributes: company_params,
                                activity_template_ids: params[:activity_template_ids],
                                custom_activities: custom_activities_param)
        render json: { company: CompanySerializer.new(company).as_json }, status: :created
      end

      # PATCH /api/v1/company
      def update
        require_company!
        return if performed?

        if CompanyProfile.update(current_company, params)
          render json: { company: CompanySerializer.new(current_company).as_json }
        else
          render_errors(current_company)
        end
      end

      # POST /api/v1/companies/:id/switch — moves the session to another of
      # this login's OWN salles: one the admin runs, or one the staff login
      # is posted to (set_workplace 404s on anything else, same as every
      # other tenant-scoped lookup).
      def switch
        current_user.switch_active_company!(@company)
        render json: { company: current_user.admin? ? CompanySerializer.new(@company).as_json : CompanySummarySerializer.new(@company, active: true).as_json }
      end

      # PUT /api/v1/companies/:id/moderators — { user_ids: [] }: exactly who
      # works at this salle among the admin's moderators. See
      # Company#post_moderators!.
      def update_moderators
        @company.post_moderators!(params[:user_ids], by: current_user)
        render json: network_json
      end

      private

      def set_workplace
        @company = current_user.workplaces.find(params[:id])
      end

      def set_owned_company
        @company = current_user.companies.find(params[:id])
      end

      def network_json
        SalleNetwork.for(current_user, current_company)
      end

      # Activities the salle names itself at signup — [{ name:, emoji: }].
      def custom_activities_param
        params.fetch(:custom_activities, []).map { |entry| entry.permit(:name, :emoji) }
      end

      def company_params(branding: true)
        CompanyProfile.attributes(params, branding: branding)
      end
    end
  end
end
