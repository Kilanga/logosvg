# One message in the conversation between a client and their designer.
class ReviewMessage < ApplicationRecord
  belongs_to :review
  belongs_to :author, class_name: "User"

  normalizes :body, with: ->(b) { b.strip }

  validates :body, presence: true, length: { maximum: 2000 }
  validate :author_is_a_party_to_the_review

  scope :unread, -> { where(read_at: nil) }

  # Written out rather than as an endless method: `def read! = x if y` parses
  # as `(def read! = x) if y`, which evaluates `y` in the class body.
  def read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def from_client? = author_id == review.client_id

  private
    # Only the two sides write here. An administrator reads a dispute; they do
    # not join the conversation.
    def author_is_a_party_to_the_review
      return if review.nil?
      return if author_id == review.client_id
      return if author_id == review.designer_profile&.user_id

      errors.add(:author, :not_a_party)
    end
end
