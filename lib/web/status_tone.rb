module Web
  # StatusBadgeComponent's one vocabulary: every status string in the app, in
  # one of five colours.
  module StatusTone
    TONES = {
      "scheduled" => "success", "confirmed" => "success", "active" => "success", "available" => "success",
      "paid" => "success", "present" => "success", "completed" => "info", "no_show" => "warning",
      "late" => "warning", "full" => "warning", "pending" => "warning", "expiring" => "warning",
      "expiring_soon" => "warning", "expired" => "danger", "cancelled" => "neutral", "failed" => "danger",
      "absent" => "danger", "unpaid" => "danger", "refunded" => "info", "trial" => "info",
      "paused" => "info", "drop_in" => "info", "inactive" => "neutral"
    }.freeze

    def self.for(status) = TONES.fetch(status.to_s, "neutral")
  end
end
