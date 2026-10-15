# One message in the conversation between a client and their designer.
class ReviewMessage < ApplicationRecord
  belongs_to :review
  belongs_to :author, class_name: "User"

  # A request for another go, a dispute and a free fix are said in the
  # conversation too, and marked as such (reported on 15/10/2026).
  KINDS = %w[ message revision dispute fix ].freeze

  normalizes :body, with: ->(b) { b.strip }

  validates :body, presence: true, length: { maximum: 2000 }
  validates :kind, inclusion: { in: KINDS }
  validate :author_is_a_party_to_the_review

  scope :unread, -> { where(read_at: nil) }

  # Written out rather than as an endless method: `def read! = x if y` parses
  # as `(def read! = x) if y`, which evaluates `y` in the class body.
  def read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def from_client? = author_id == review.client_id

  def plain? = kind == "message"

  # G3, decided on 15/10/2026: the other side is told by email — once, on the
  # first message they have not read, and not again until they have been back
  # to read it. Each email costs one of the day's Brevo sends. The other kinds
  # come with an email of their own already.
  after_create_commit :notify_other_party, if: :plain?

  private
    def notify_other_party
      earlier_unread = ReviewMessage.unread.where(review_id: review_id, author_id: author_id).where.not(id: id)
      return if earlier_unread.exists?

      ReviewMailer.new_message(self).deliver_later
    end

    # Only the two sides write here. An administrator reads a dispute; they do
    # not join the conversation.
    def author_is_a_party_to_the_review
      return if review.nil?
      return if author_id == review.client_id
      return if author_id == review.read_association(:designer_profile)&.user_id

      errors.add(:author, :not_a_party)
    end
end
