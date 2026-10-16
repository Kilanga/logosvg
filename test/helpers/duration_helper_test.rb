require "test_helper"

class DurationHelperTest < ActionView::TestCase
  test "a short wait, the way one says it" do
    assert_equal "45 s", duration_in_words_short(45)
    assert_equal "2 min", duration_in_words_short(120)
    assert_equal "2 min 10 s", duration_in_words_short(130)
    assert_equal "1 h 05", duration_in_words_short(3900)
  end
end
