# `:midday` — the example runs at noon, gym time (Africa/Tunis, a
# company's default zone), whatever the clock says. For an example built on
# "in an hour" or "in three days" that must stay the same day: run late in
# the evening, it would otherwise cross midnight at the gym and fail.
RSpec.configure do |config|
  config.around(:each, :midday) do |example|
    travel_to(Time.find_zone("Africa/Tunis").now.change(hour: 12)) { example.run }
  end
end
