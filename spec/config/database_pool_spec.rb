require "rails_helper"

# Puma's threads and Action Cable's workers (live notifications, served by
# the same process) draw from one connection pool. Sized for the threads
# alone, a burst of notifications makes requests wait for a connection and
# fail with ActiveRecord::ConnectionTimeoutError.
RSpec.describe "Database connection pool" do
  it "covers the server's threads and Action Cable's workers" do
    threads = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
    cable_workers = ActionCable.server.config.worker_pool_size

    expect(ActiveRecord::Base.connection_pool.size).to be >= threads + cable_workers
  end
end
