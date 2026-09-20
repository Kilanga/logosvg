# A term a prompt may not contain.
#
# Checked on this side before the generator is called, so a refused prompt
# costs the client no allowance and never reaches another machine. The service
# keeps its own list too — this one is the platform's, and an administrator
# edits it without a deploy.
class BlockedTerm < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  # Folded on the way in, so "Nike" and "nike" are one row rather than two.
  normalizes :term, with: ->(t) { t.to_s.strip.downcase }

  validates :term, presence: true, uniqueness: true, length: { minimum: 2, maximum: 60 }

  scope :active, -> { where(active: true) }
  scope :by_usage, -> { order(hits_count: :desc, term: :asc) }

  # The terms a prompt is checked against, cached: this runs on every
  # generation, and the list changes a few times a year.
  CACHE_KEY = "blocked_terms/active".freeze
  CACHE_TTL = 10.minutes

  def self.terms
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { active.pluck(:term) }
  end

  def self.reset_cache! = Rails.cache.delete(CACHE_KEY)

  # The first term the text contains, or nil. Matched on word boundaries so
  # "art" does not catch "cartes" — a list that refuses innocent prompts is one
  # the administration will be asked to remove.
  def self.matching(text)
    haystack = text.to_s.downcase
    terms.find { |term| haystack.match?(/(?<![[:alnum:]])#{Regexp.escape(term)}(?![[:alnum:]])/) }
  end

  # Counted rather than logged: how often a term catches something is what
  # tells an administrator whether it earns its place.
  def self.record_hit!(term)
    where(term: term).update_all("hits_count = hits_count + 1, last_hit_at = NOW()")
  end

  after_commit :reset_cache

  private
    def reset_cache = self.class.reset_cache!
end
