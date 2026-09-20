# A level a designer accepts. The join carries no data of its own: what matters
# is that the pair exists.
class DesignerLevel < ApplicationRecord
  belongs_to :designer_profile
  belongs_to :review_level

  validates :review_level_id, uniqueness: { scope: :designer_profile_id }
end
