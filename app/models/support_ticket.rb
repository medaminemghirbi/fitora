# A problem report from the admin's Support page, with optional file/video
# attachments — reviewed by a Fitora superadmin from a cross-company inbox.
class SupportTicket < ApplicationRecord
  # How many of a gym's tickets its history lists, most recent first.
  LIST_LIMIT = 50

  ALLOWED_ATTACHMENT_TYPES = %w[
    image/jpeg image/png image/webp image/gif
    application/pdf
    video/mp4 video/quicktime video/webm
  ].freeze
  MAX_ATTACHMENT_SIZE = 100.megabytes
  MAX_ATTACHMENTS = 5

  belongs_to :company
  belongs_to :created_by, class_name: "User"

  has_many_attached :attachments

  enum :status, { open: 0, resolved: 1 }

  validates :subject, :message, presence: true
  validate :attachments_are_valid

  scope :recent, -> { order(created_at: :desc) }

  # The superadmin console's support table.
  console_searchable attributes: %i[subject message status created_at], associations: %i[company created_by]

  private

  def attachments_are_valid
    return unless attachments.attached?

    if attachments.count > MAX_ATTACHMENTS
      errors.add(:attachments, "cannot include more than #{MAX_ATTACHMENTS} files")
    end

    attachments.each do |file|
      unless file.content_type.in?(ALLOWED_ATTACHMENT_TYPES)
        errors.add(:attachments, "must be an image, a video, or a PDF")
        break
      end
    end

    attachments.each do |file|
      if file.blob.byte_size > MAX_ATTACHMENT_SIZE
        errors.add(:attachments, "must each be smaller than #{MAX_ATTACHMENT_SIZE / 1.megabyte}MB")
        break
      end
    end
  end
end
