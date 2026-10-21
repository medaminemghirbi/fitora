# Saving and removing a gym's rooms, shared by /api/v1/spaces and the web
# UI's rooms page (moved unchanged from Api::V1::SpacesController).
module RoomEditor
  # Saves `space` with `attributes` (name, kind, capacity, active) and, when
  # given, the activities it is reserved for — only this gym's. Returns
  # whether it saved; the errors are on `space`.
  def self.save(space, attributes, activity_ids: :unchanged)
    space.assign_attributes(attributes)
    return false unless space.save

    unless activity_ids == :unchanged
      space.activity_ids = space.company.activities.where(id: Array(activity_ids)).pluck(:id)
    end
    true
  end

  # A room with nothing upcoming goes; one still holding sessions is only
  # switched off.
  def self.remove(space)
    space.deletable? ? space.destroy! : space.update!(active: false)
    space
  end
end
