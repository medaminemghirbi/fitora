module Web
  module Member
    # What the member's app opens on (MemberScheduleComponent): the gym's
    # upcoming sessions, as GET /api/v1/me/sessions answers them for the gym
    # shown — refused as it is refused when no gym of theirs has the app,
    # which the Angular page shows as its error state.
    class ScheduleController < BaseController
      def show
        @sessions = gym && JSON.parse(MemberApp.sessions(current_client, [ gym.id ]).to_json).map(&:deep_symbolize_keys)
      end
    end
  end
end
