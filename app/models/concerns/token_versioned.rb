# Every JWT carries the token_version its account had when it was issued
# (see JwtService). Moving the version on ends every session at once — which
# is what a new password, a deactivated account or "sign out everywhere"
# should mean. Shared by User and Client.
#
# The live connection (/cable) is checked only as it opens, so one open
# when the version moves is closed too. The browser reconnects at once, and
# the new connection is checked like any other: the session that changed the
# password carries on, the ones it ended do not.
module TokenVersioned
  extend ActiveSupport::Concern

  included do
    before_save :end_existing_sessions, if: :sessions_should_end?
    after_commit :end_live_connections, if: :saved_change_to_token_version?
  end

  # Signs out every device. The caller issues a fresh token if the person
  # making the request should stay signed in on this one.
  def revoke_all_tokens!
    increment!(:token_version) # rubocop:disable Rails/SkipsModelValidations
    end_live_connections
  end

  # Once the new version is committed, so a reconnection cannot read the old
  # one. Named by both of ApplicationCable::Connection's identifiers, the
  # other one empty, as the connection itself is.
  def end_live_connections
    client = is_a?(Client)
    ActiveRecord.after_all_transactions_commit do
      ActionCable.server.remote_connections.where(current_user: (self unless client), current_client: (self if client)).disconnect
    end
  end

  def token_current?(version)
    token_version == version.to_i
  end

  private

  def sessions_should_end?
    return false if new_record?

    will_save_change_to_password_digest? || (will_save_change_to_active? && !active?)
  end

  def end_existing_sessions
    self.token_version += 1
  end
end
