require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # One browser at a time. System tests are memory-hungry, and running several
  # Chrome instances in parallel is what makes them flaky on small machines and
  # on CI runners alike.
  parallelize(workers: 1)

  # Turbo turns every navigation into a fetch, and this machine is slow. Two
  # seconds is enough on a developer laptop and not on a CI runner or an old
  # dual-core; waiting longer costs nothing when the assertion passes.
  #
  # Raised from 5 to 10 once the suite grew past twenty browser tests: a
  # sign-in redirect that normally lands in well under a second occasionally
  # overran five when the machine was loaded, and the failure looked like a
  # broken assertion rather than a slow one.
  Capybara.default_max_wait_time = 10

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
  def displayed(key, **options) = shown(I18n.t(key, **options))

  # Same, for a literal that is not a translation — a shop name read from a
  # fixture, say, which the display face also uppercases.
  def shown(text) = /#{Regexp.escape(text)}/i
end
