module ApplicationCable
  # Opens with a cable ticket (POST /api/v1/cable_ticket): browsers can't set
  # headers on a WebSocket handshake, so the credential rides in the query
  # string (?ticket=...). A ticket lasts 30 seconds and opens one connection,
  # so the copy that access logs keep is worthless — unlike the login token
  # that used to travel here.
  #
  # The server-rendered web UI opens it without a ticket: same origin, its
  # session cookie goes along, and the session is checked as the pages check
  # it (Web::SessionAccount). The handshake's Origin is checked against
  # allowed_request_origins, which is what keeps another site from opening
  # one with that cookie.
  #
  # A connection is either a User's (admin, superadmin) or a Client's (a member on
  # their own app), never both.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_client

    def connect
      return connect_web_session if request.params[:ticket].blank?

      claims = verified_ticket
      if claims[:client_id]
        self.current_client = find_current(Client, claims)
      else
        self.current_user = find_current(User, claims)
      end
    end

    private

    def connect_web_session
      session = cookies.encrypted[Rails.application.config.session_options[:key]]
      found = Web::SessionAccount.resolve(session.is_a?(Hash) ? session[Web::Authentication::SESSION_KEY.to_s] : nil)
      reject_unauthorized_connection if found.account.nil?

      self.current_user = found.user
      self.current_client = found.client
    end

    def verified_ticket
      ticket = request.params[:ticket].to_s
      claims = JwtService.decode_cable_ticket(ticket)
      reject_unauthorized_connection unless first_use?(claims[:jti])
      claims
    rescue JwtService::DecodeError
      reject_unauthorized_connection
    end

    def find_current(model, claims)
      account = model.active.find_by(id: claims[:client_id] || claims[:user_id])
      return account if account&.token_current?(claims[:token_version])

      reject_unauthorized_connection
    end

    # Redis remembers each ticket past its expiry, so a replay within the
    # 30 seconds is refused too.
    def first_use?(jti)
      return false if jti.blank?

      Sidekiq.redis { |redis| redis.call("SET", "cable_ticket:#{jti}", "1", "NX", "EX", 60) } == "OK"
    end
  end
end
