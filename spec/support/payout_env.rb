# Fitora's own bank details come from the environment (PayoutAccount). A
# developer's .env may set them; CI has none. Every example starts without
# them, as on CI — a spec that needs them sets them itself — so every
# response, and doc/openapi.yaml written from them, is the same on every
# machine. Before each example, not the suite: dotenv puts ENV back after
# every example in the test environment (Dotenv autorestore).
RSpec.configure do |config|
  config.before do
    %w[FITORA_RIB FITORA_BANK_NAME FITORA_ACCOUNT_HOLDER FITORA_SWIFT].each { |key| ENV.delete(key) }
  end
end
