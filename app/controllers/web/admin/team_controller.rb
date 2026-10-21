module Web
  module Admin
    # The team (TeamComponent): coaches and back-office logins in one list,
    # filtered, searched and paged in the browser (team-page); created in a
    # drawer and edited in three modals, each write through the rules
    # /api/v1/coaches and /api/v1/staff apply (Team::Actions), behind the
    # same capabilities, answered with the API's message (K-04).
    class TeamController < BaseController
      before_action -> { require_capability(:coaches) }, only: :index
      before_action :refuse_without_coaches, only: %i[show_coach create_coach update_coach deactivate_coach set_login]
      before_action :refuse_unless_admin, only: %i[create_staff update_staff]
      before_action :set_coach, only: %i[show_coach update_coach deactivate_coach set_login]

      rescue_from ActiveRecord::RecordInvalid, with: ->(invalid) { render_errors(invalid.record) }
      rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "Resource not found" }, status: :not_found }
      rescue_from ActionController::ParameterMissing, with: ->(missing) { render json: { error: missing.message }, status: :bad_request }

      helper_method :team_roles, :team_role_name

      # The page; with ?fragment=1 only what load() redraws (the count, the
      # tabs and pills, the cards), which the page swaps in after a save.
      def index
        @members = members
        return render(partial: "web/admin/team/parts", locals: { members: @members }) if params[:fragment].present?

        # ?action=new (the command palette's "new member"): the drawer open,
        # on the back-office form when asked for and allowed.
        @open = (params[:type] == "backoffice" && current_user.admin? ? "backoffice" : "coach") if request.query_parameters["action"] == "new"
      end

      # GET — the whole addresses an admin's edit forms take (masked for
      # anyone else), as GET /api/v1/coaches/:id.
      def show_coach
        render json: { coach: CoachSerializer.new(@coach, reveal: current_user.admin?).as_json }
      end

      def create_coach
        coach = current_company.coaches.new(coach_params)
        return render_errors(coach) unless coach.save

        render json: { coach: CoachSerializer.new(coach.reload).as_json }, status: :created
      end

      def update_coach
        return render_errors(@coach) unless @coach.update(coach_params)

        render json: { coach: CoachSerializer.new(@coach).as_json }
      end

      # Soft, as DELETE /api/v1/coaches/:id.
      def deactivate_coach
        @coach.update!(active: false)
        render json: { coach: CoachSerializer.new(@coach).as_json }
      end

      def set_login
        Team::Actions.set_coach_login!(@coach, company: current_company, by: current_user, email: params[:email], password: params[:password])
        render json: { coach: CoachSerializer.new(@coach.reload).as_json }
      rescue Team::Actions::Forbidden => e
        render json: { error: e.message }, status: :forbidden
      end

      def create_staff
        staff_member = Team::Actions.create_staff!(
          company: current_company, by: current_user,
          user_attributes: params.require(:staff_member).permit(:first_name, :last_name, :email, :phone, :password, :locale).to_h.symbolize_keys,
          staff_attributes: staff_params
        )
        render json: { staff_member: StaffMemberSerializer.new(staff_member).as_json }, status: :created
      end

      def update_staff
        staff_member = current_company.staff_members.find(params[:id])
        return render_errors(staff_member) unless Team::Actions.update_staff(staff_member, company: current_company, by: current_user, staff_attributes: staff_params)

        render json: { staff_member: StaffMemberSerializer.new(staff_member).as_json }
      end

      private

      # TeamComponent#members: one entry per person — each coach (with the
      # staff login attached to it, if any), then each back-office login
      # that is not a coach's — sorted by name as localeCompare sorts.
      def members
        coaches = current_company.coaches.includes(staff_member: :user).order(:first_name).map { |c| CoachSerializer.new(c).as_json }
        # Only the admin manages logins (GET /api/v1/staff is theirs).
        staff = current_user.admin? ? current_company.staff_members.includes(:user, :coach, :assigned_role).map { |s| StaffMemberSerializer.new(s).as_json } : []
        staff_by_coach = staff.select { |s| s[:coach_id] }.index_by { |s| s[:coach_id] }

        from_coaches = coaches.map do |c|
          { key: "coach:#{c[:id]}", name: c[:full_name], email: c[:email], phone: c[:phone], active: c[:active], bio: c[:bio],
            has_mobile: c[:has_login], has_web: false, role_name: team_role_name("coach"), coach: c, staff: nil,
            staff_member_id: staff_by_coach[c[:id]]&.dig(:id) }
        end
        # A coach's own login is a staff record too; the coach's entry stands
        # for it. Angular filters on `role`, which the API stopped sending
        # (b82e27e: "a coach login is one with a Coach row" — is_coach), so
        # it lists every coach twice (B-08).
        from_staff = staff.reject { |s| s[:is_coach] }.map do |s|
          { key: "staff:#{s[:id]}", name: s[:user][:full_name], email: s[:user][:email], phone: s[:user][:phone], active: s[:active], bio: nil,
            has_mobile: false, has_web: true, role_name: team_role_name(s[:role_key]), coach: nil, staff: s, staff_member_id: s[:id] }
        end
        Web::Collation.sort(from_coaches + from_staff) { |m| m[:name] }
      end

      # The salle's roles, as the bootstrap lists them.
      def team_roles
        Array(bootstrap[:roles])
      end

      # ConfigurationService#roleName: the role's own name, or its key
      # capitalised.
      def team_role_name(key)
        team_roles.find { |r| r[:key] == key }&.dig(:name) || key.to_s.capitalize
      end

      def set_coach
        @coach = current_company.coaches.find(params[:id])
      end

      def coach_params
        params.require(:coach).permit(:first_name, :last_name, :email, :phone, :bio, :photo_url, :active, :birthdate)
      end

      def staff_params
        params.require(:staff_member).permit(:role, :role_id, :active, :coach_id, :birthdate).to_h.symbolize_keys
      end

      def refuse_without_coaches
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden unless capability?(:coaches)
      end

      def refuse_unless_admin
        render json: { error: "You are not allowed to perform this action" }, status: :forbidden unless current_user.admin?
      end

      def render_errors(record)
        messages = I18n.with_locale(:en) { record.errors.full_messages }
        render json: { error: messages.first || "Validation failed", errors: messages }, status: :unprocessable_content
      end
    end
  end
end
