require "rails_helper"

RSpec.describe NotificationChannel, type: :channel do
  let(:company) { create(:company) }

  it "streams for the connected user" do
    stub_connection current_user: company.admin, current_client: nil
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(company.admin)
  end

  it "streams for a connected member" do
    member = create(:client, company: company)
    stub_connection current_user: nil, current_client: member
    subscribe
    expect(subscription).to have_stream_for(member)
  end
end

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user, :admin) }

  it "opens with a cable ticket" do
    connect "/cable?ticket=#{JwtService.cable_ticket_for(user)}"
    expect(connection.current_user).to eq(user)
  end

  it "opens for a member with theirs" do
    member = create(:client, password: "member-pass-1")
    connect "/cable?ticket=#{JwtService.cable_ticket_for(member)}"
    expect(connection.current_client).to eq(member)
  end

  it "opens once per ticket" do
    ticket = JwtService.cable_ticket_for(user)
    connect "/cable?ticket=#{ticket}"

    expect { connect "/cable?ticket=#{ticket}" }.to have_rejected_connection
  end

  it "no longer takes the login token in the URL" do
    expect { connect "/cable?token=#{JwtService.for_user(user)}" }.to have_rejected_connection
    expect { connect "/cable?ticket=#{JwtService.for_user(user)}" }.to have_rejected_connection
  end

  it "refuses an expired ticket, and one from before a password change" do
    stale = JwtService.cable_ticket_for(user)
    travel(31.seconds) { expect { connect "/cable?ticket=#{stale}" }.to have_rejected_connection }

    before_change = JwtService.cable_ticket_for(user)
    user.update!(password: "brand-new-pass-1")
    expect { connect "/cable?ticket=#{before_change}" }.to have_rejected_connection
  end

  it "rejects a missing or bad ticket" do
    expect { connect "/cable" }.to have_rejected_connection
    expect { connect "/cable?ticket=garbage" }.to have_rejected_connection
  end

  describe "the web UI's session cookie (no ticket)" do
    def web_session(account, **claims)
      kind = account.is_a?(Client) ? "client" : "user"
      claims = { "kind" => kind, "id" => account.id, "tv" => account.token_version, "exp" => 7.days.from_now.to_i }.merge(claims)
      cookies.encrypted["_fitora_session"] = { value: { "fitora" => claims } }
    end

    it "opens for the signed-in account, a member's too" do
      web_session(user)
      connect "/cable"
      expect(connection.current_user).to eq(user)

      member = create(:client, password: "member-pass-1")
      web_session(member)
      connect "/cable"
      expect(connection.current_client).to eq(member)
    end

    it "refuses a session the pages would refuse: expired, signed out everywhere, an impersonation's superadmin gone" do
      web_session(user, "exp" => 1.minute.ago.to_i)
      expect { connect "/cable" }.to have_rejected_connection

      web_session(user, "tv" => user.token_version - 1)
      expect { connect "/cable" }.to have_rejected_connection

      former = create(:user, :admin)
      web_session(user, "imp" => former.id)
      expect { connect "/cable" }.to have_rejected_connection
    end

    it "opens for an impersonated admin as the admin" do
      web_session(user, "imp" => create(:user, :superadmin).id)
      connect "/cable"
      expect(connection.current_user).to eq(user)
    end
  end
end

RSpec.describe "POST /api/v1/cable_ticket", type: :request do
  it "hands a signed-in account a ticket that is not itself a login" do
    user = create(:user, :admin)
    post "/api/v1/cable_ticket", headers: auth_headers(user)
    ticket = response.parsed_body["ticket"]

    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{ticket}" }
    expect(response).to have_http_status(:unauthorized)
  end
end
