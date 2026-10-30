# A sign-out that holds for a copy of what was signed out, too. The web
# session is a cookie and the API's login a JWT: the server keeps neither, so
# forgetting one on the device used to leave any copy of it good until it
# expired. Each now carries an id ("sid" in the session, "jti" in the token),
# and signing out writes that id here until the moment it would have expired
# anyway. Web::SessionAccount and ApplicationController#authenticate_request!
# refuse an id found here.
#
# Ids only, never the token itself. A session or token from before ids were
# given has none, and runs out its own expiry as before. Redis unreachable,
# nothing is refused: what reaches here has already been checked as genuine,
# unexpired and at its account's token_version, as before this list existed.
module RevokedSessions
  def self.revoke!(id, expires_at)
    ttl = expires_at.to_i - Time.current.to_i
    return if id.blank? || ttl <= 0

    Sidekiq.redis { |redis| redis.call("SET", key(id), "1", "EX", ttl) }
  rescue RedisClient::Error => e
    Rails.logger.warn("Sign-out of #{id} not recorded: #{e.class}")
  end

  def self.revoked?(id)
    return false if id.blank?

    Sidekiq.redis { |redis| redis.call("EXISTS", key(id)) } == 1
  rescue RedisClient::Error => e
    Rails.logger.warn("Signed-out sessions unreadable: #{e.class}")
    false
  end

  def self.key(id) = "revoked_session:#{id}"
end
