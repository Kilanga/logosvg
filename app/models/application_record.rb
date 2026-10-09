class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # The associated record, whether or not whoever loaded this one asked for it.
  #
  # Development runs with `strict_loading_by_default`: reaching an association
  # nobody preloaded raises there, and only there — the test suite and
  # production do not set it. A model method that reads an association
  # cannot know how its caller loaded the record, so it asks here: the
  # preloaded record when there is one, else one query of its own, which
  # strict loading allows. For belongs_to and has_one only.
  def read_association(name)
    association = association(name)
    return association.target if association.loaded?

    reflection = association.reflection
    if reflection.belongs_to?
      key = self[reflection.foreign_key]
      key && reflection.klass.find_by(reflection.association_primary_key => key)
    else
      reflection.klass.find_by(reflection.foreign_key => self[reflection.active_record_primary_key])
    end
  end
end
