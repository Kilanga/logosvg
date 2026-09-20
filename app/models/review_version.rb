# One file handed back by the designer.
#
# The file has to match the design's own `print_format`: a designer does not
# return a PNG where the workshop expects an SVG. What the inspection found is
# kept on the row so the client and the workshop can read it without opening
# anything.
class ReviewVersion < ApplicationRecord
  belongs_to :review

  has_one_attached :file

  validates :number, presence: true, numericality: { greater_than: 0 },
                     uniqueness: { scope: :review_id }
  validates :file, presence: true

  before_validation :assign_number, on: :create

  def vector? = review.design.vector?

  private
    # Continuous within the review. Taken from the rows rather than counted,
    # so a deleted version does not hand its number to the next one.
    def assign_number
      self.number ||= (review.versions.maximum(:number) || 0) + 1
    end
end
