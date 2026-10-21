module Web
  # The coach shell's small decisions, as its Angular components make them.
  module CoachHelper
    # The roster card's title (CoachTodayComponent): "🧘 Yoga — 18:00".
    def coach_session_label(session)
      "#{session[:activity_emoji].present? ? "#{session[:activity_emoji]} " : ""}#{session[:activity_name]} — #{ng_date(session[:starts_at], "HH:mm")}"
    end

    # CoachMembersComponent#isLapsed: no session ahead, and not seen for
    # three weeks or more.
    def coach_member_lapsed?(member)
      return false if member[:next_session_at] || member[:last_seen_at].nil?

      (Time.current - Time.zone.parse(member[:last_seen_at])) / 1.day >= 21
    end
  end
end
