module Web
  module Routing
    # A salle's id, as the admin, desk and coach shells carry it in the path
    # (MIGRATION_AUDIT §8.1).
    SALLE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
  end
end
