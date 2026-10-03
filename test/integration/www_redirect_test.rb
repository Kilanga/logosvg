require "test_helper"

# www.<domaine> est accepté par le proxy et par config.hosts, mais une seule
# adresse fait foi : tout ce qui arrive sur www repart vers le nom nu.
class WwwRedirectTest < ActionDispatch::IntegrationTest
  setup { Rails.application.config.x.canonical_host = "example.com" }
  teardown { Rails.application.config.x.canonical_host = nil }

  test "www redirects permanently to the bare domain, path and query kept" do
    host! "www.example.com"
    get "/imprimeurs?technique=dtf"

    assert_response :moved_permanently
    assert_equal "http://example.com/imprimeurs?technique=dtf", response.location
  end

  test "the root of www redirects too" do
    host! "www.example.com"
    get "/"

    assert_redirected_to "http://example.com/"
  end

  test "the bare domain is served normally" do
    host! "example.com"
    get "/"

    assert_response :success
  end
end

class WwwRedirectWithoutCanonicalHostTest < ActionDispatch::IntegrationTest
  test "without a canonical host, www is served as is" do
    get "/"

    assert_response :success
  end
end
