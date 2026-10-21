// StatusBadgeComponent's tone for a status (Web::StatusTone).
const TONES = {
  scheduled: "success", confirmed: "success", active: "success", available: "success",
  paid: "success", present: "success", completed: "info", no_show: "warning",
  late: "warning", full: "warning", pending: "warning", expiring: "warning",
  expiring_soon: "warning", expired: "danger", cancelled: "neutral", failed: "danger",
  absent: "danger", unpaid: "danger", refunded: "info", trial: "info",
  paused: "info", drop_in: "info", inactive: "neutral",
}

export const statusTone = (status) => TONES[status] ?? "neutral"
