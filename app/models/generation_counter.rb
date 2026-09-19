# One row per client per day. The logic lives in GenerationQuota; this is the
# table it counts in.
class GenerationCounter < ApplicationRecord
  belongs_to :user

  validates :day, presence: true
  validates :count, numericality: { greater_than_or_equal_to: 0 }
end
