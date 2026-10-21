module WebHelper
  # Signs in through the web UI's own form, as a person would.
  def web_sign_in(account, password: "password123")
    post "/connexion", params: { email: account.email, password: password }
  end

  # The members a members page lists, in order — read off the rows' links.
  def listed_client_ids(html = response.body)
    html.scan(%r{data-href="/admin/[0-9a-f-]{36}/clients/([0-9a-f-]{36})"}).flatten
  end
end

RSpec.configure do |config|
  config.include WebHelper, type: :request
end
