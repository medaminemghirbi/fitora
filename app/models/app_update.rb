# A platform changelog entry — what the superadmin team shipped, with optional
# screenshots/screen-recordings. The latest row's `version` is what the
# admin/superadmin shells show as the running app version. Publishing one fans
# out a real-time "system_update" Notification to every other superadmin (see
# Api::V1::Superadmin::AppUpdatesController#create).
class AppUpdate < ApplicationRecord
  # How many release notes a list shows, most recent first.
  LIST_LIMIT = 50

  ALLOWED_MEDIA_TYPES = %w[
    image/jpeg image/png image/webp image/gif
    video/mp4 video/quicktime video/webm
  ].freeze
  MAX_MEDIA_SIZE = 100.megabytes
  MAX_MEDIA_ITEMS = 8

  belongs_to :created_by, class_name: "User"

  has_many_attached :media

  validates :version, :title, presence: true
  validate :media_is_valid

  before_validation :stamp_published_at, on: :create

  scope :recent, -> { order(published_at: :desc) }

  def self.current_version
    recent.first&.version
  end

  private

  def stamp_published_at
    self.published_at ||= Time.current
  end

  def media_is_valid
    return unless media.attached?

    if media.count > MAX_MEDIA_ITEMS
      errors.add(:media, "cannot include more than #{MAX_MEDIA_ITEMS} files")
    end

    media.each do |file|
      unless file.content_type.in?(ALLOWED_MEDIA_TYPES)
        errors.add(:media, "must be an image or a video")
        break
      end
    end

    media.each do |file|
      if file.blob.byte_size > MAX_MEDIA_SIZE
        errors.add(:media, "must each be smaller than #{MAX_MEDIA_SIZE / 1.megabyte}MB")
        break
      end
    end
  end
end
