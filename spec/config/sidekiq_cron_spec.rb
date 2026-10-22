require "rails_helper"

# A class name in config/sidekiq_cron.yml that does not exist only logs an
# error when Sidekiq starts, and the job silently never runs.
RSpec.describe "config/sidekiq_cron.yml" do
  schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))

  schedule.each do |name, entry|
    it "#{name} schedules a job that exists" do
      expect(entry["class"].safe_constantize).to be < ApplicationJob
      expect(Fugit::Cron.parse(entry["cron"])).not_to be_nil
    end
  end
end
