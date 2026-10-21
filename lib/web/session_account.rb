module Web
  # Who a web session's claims name, if they still stand — checked the way
  # ApplicationController#authenticate_request! checks a token
  # (MIGRATION_AUDIT §9.1): not expired, the account active and at its
  # current token_version, and an impersonation's superadmin still one.
  # Read by the pages (Web::Authentication) and by the live connection
  # (ApplicationCable::Connection), so both accept the same sessions.
  module SessionAccount
    Result = Struct.new(:user, :client, :impersonator, keyword_init: true) do
      def account = user || client
    end

    NONE = Result.new.freeze

    def self.resolve(claims)
      return NONE if claims.blank? || claims["exp"].to_i <= Time.current.to_i

      if claims["kind"] == "client"
        client = Client.active.find_by(id: claims["id"])
        return client&.token_current?(claims["tv"].to_i) ? Result.new(client: client) : NONE
      end

      user = User.active.find_by(id: claims["id"])
      return NONE unless user&.token_current?(claims["tv"].to_i)
      return Result.new(user: user) unless claims["imp"]

      impersonator = User.active.superadmin.find_by(id: claims["imp"])
      impersonator ? Result.new(user: user, impersonator: impersonator) : NONE
    end
  end
end
