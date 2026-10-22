# Every night: deletes what has stopped being useful, so the two tables that
# only ever grow stay the size of what anyone still reads.
#
# - A notification someone has read, after 90 days; any notification, after a
#   year. Their dedup keys are tied to an event long past by then (a
#   contract's expiry date, a booking's session, a year's birthday, a release),
#   so no scan sends one again.
# - An audit log entry, after two years.
#
# In batches, so no statement holds a long lock on a busy table.
class PruneOldRecordsJob < ApplicationJob
  queue_as :default

  READ_NOTIFICATIONS_KEPT = 90.days
  NOTIFICATIONS_KEPT = 1.year
  AUDIT_LOGS_KEPT = 2.years
  BATCH_SIZE = 1_000

  def perform
    now = Time.current
    prune(Notification.where.not(read_at: nil).where(created_at: ...now - READ_NOTIFICATIONS_KEPT))
    prune(Notification.where(created_at: ...now - NOTIFICATIONS_KEPT))
    prune(AuditLog.where(created_at: ...now - AUDIT_LOGS_KEPT))
  end

  private

  def prune(scope)
    scope.in_batches(of: BATCH_SIZE).delete_all
  end
end
