class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # A write the gym's rules turn down — "this session is full", "this is
  # already paid" — with the reason in words the person asking can act on.
  # Raised from a model method, it rolls back the transaction it is in, and
  # ApplicationController answers it with a 422 in the same shape a failed
  # validation gets.
  class Refused < StandardError; end

  # What the superadmin console's tables (Web::DataTable) may search, sort
  # and filter a model by: Ransack's allowlists, granted to the console alone
  # (auth_object :superadmin). Anywhere else a ransack search has nothing to
  # search by, so a gym-scoped page can never reach across tenants through
  # one. Never a secret here: no digest, no token, no key.
  def self.console_searchable(attributes: [], associations: [], scopes: [])
    attributes = attributes.map(&:to_s).freeze
    associations = associations.map(&:to_s).freeze
    scopes = scopes.map(&:to_sym).freeze
    define_singleton_method(:ransackable_attributes) { |auth_object = nil| auth_object == :superadmin ? attributes : [] }
    define_singleton_method(:ransackable_associations) { |auth_object = nil| auth_object == :superadmin ? associations : [] }
    define_singleton_method(:ransackable_scopes) { |auth_object = nil| auth_object == :superadmin ? scopes : [] }
  end

  # Ransack asks every model; one the console does not read answers nothing.
  console_searchable
end
