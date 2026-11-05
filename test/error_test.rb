# frozen_string_literal: true

require "test_helper"

class ErrorTest < Minitest::Test
  def test_from_response_defaults
    err = WebCrawlerAPI::Error.from_response(500, nil)
    assert_equal "unknown_error", err.error_code
    assert_equal "Unknown error", err.message
    assert_equal 500, err.status_code
  end

  def test_is_standard_error
    assert_operator WebCrawlerAPI::Error, :<, StandardError
  end
end
