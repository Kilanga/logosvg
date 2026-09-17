require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # One browser at a time. System tests are memory-hungry, and running several
  # Chrome instances in parallel is what makes them flaky on small machines and
  # on CI runners alike.
  parallelize(workers: 1)

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |options|
    # Chrome runs inside WSL here and inside a container on CI. Neither offers a
    # usable sandbox or a large enough /dev/shm.
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    # Keep rendering identical everywhere, so screenshots of a failure are
    # comparable between a laptop and CI.
    options.add_argument("--force-device-scale-factor=1")
    options.add_argument("--lang=fr-FR")
  end

  # Display headings are uppercased in CSS, and a browser reports text as it is
  # rendered, not as it is written. Matching a translation case-insensitively
  # asserts that the right words are on screen without freezing a styling
  # decision into the test.
  def displayed(key, **options)
    /#{Regexp.escape(I18n.t(key, **options))}/i
  end
end
