# frozen_string_literal: true

require "test_helper"

class BatchTest < Minitest::Test
  include TestHelpers

  def test_scrape_batch_async_maps_url_array_to_urls
    stub = stub_request(:post, "#{BASE}/v2/batch/scrape")
           .with(body: hash_including("urls" => ["https://a.com", "https://b.com"], "max_concurrency" => 5))
           .to_return(json_response("id" => "b1", "status_url" => "x", "invalid_urls" => []))

    res = client.scrape_batch_async(url: ["https://a.com", "https://b.com"], max_concurrency: 5)

    assert_requested stub
    assert_equal "b1", res.id
  end

  def test_scrape_with_array_polls_until_finished
    stub_request(:post, "#{BASE}/v2/batch/scrape").to_return(json_response("id" => "b1"))
    stub_request(:get, "#{BASE}/v2/batch/scrape/b1").to_return(
      json_response("id" => "b1", "status" => "scraping", "total" => 2),
      json_response("id" => "b1", "status" => "completed", "total" => 2, "data" => [{ "url" => "https://a.com" }],
                    "next" => "c2")
    )

    res = client.scrape(url: ["https://a.com", "https://b.com"])

    assert_equal "completed", res.status
    assert_equal "c2", res.next
    assert_equal 1, res.data.length
    assert_equal [2.0], @sleeps
  end

  def test_scrape_with_string_keeps_single_behavior
    stub_request(:post, "#{BASE}/v2/scrape?async=true").to_return(json_response("id" => "s1"))
    stub_request(:get, "#{BASE}/v2/scrape/s1").to_return(json_response("status" => "done", "markdown" => "ok"))

    assert_equal "ok", client.scrape(url: "https://a.com").markdown
  end

  def test_batch_timeout
    stub_request(:post, "#{BASE}/v2/batch/scrape").to_return(json_response("id" => "b1"))
    stub_request(:get, "#{BASE}/v2/batch/scrape/b1").to_return(json_response("status" => "scraping"))

    err = assert_raises(WebCrawlerAPI::Error) { client.scrape_batch({ url: ["https://a.com"] }, 2) }
    assert_equal "timeout", err.error_code
  end

  def test_get_batch_sends_limit_and_cursor
    stub = stub_request(:get, "#{BASE}/v2/batch/scrape/b1?limit=50&cursor=abc")
           .to_return(json_response("id" => "b1", "status" => "completed", "next" => ""))

    client.get_batch("b1", limit: 50, cursor: "abc")

    assert_requested stub
  end

  def test_get_batch_errors
    stub_request(:get, "#{BASE}/v2/batch/scrape/b1/errors")
      .to_return(json_response("errors" => [{ "url" => "u", "error_code" => "e" }], "robots_blocked" => []))

    res = client.get_batch_errors("b1")
    assert_equal "e", res.errors.first["error_code"]
  end

  def test_cancel_batch
    stub = stub_request(:delete, "#{BASE}/v2/batch/scrape/b1").to_return(json_response("status" => "canceled"))

    assert_equal "canceled", client.cancel_batch("b1").status
    assert_requested stub
  end

  def test_batch_api_error
    stub_request(:post, "#{BASE}/v2/batch/scrape")
      .to_return(json_response({ "error_code" => "invalid_request", "error_message" => "no valid urls" }, status: 400))

    err = assert_raises(WebCrawlerAPI::Error) { client.scrape(url: ["bad"]) }
    assert_equal 400, err.status_code
  end
end

class OptionalAttributesTest < Minitest::Test
  def test_absent_optional_fields_return_nil_but_typos_still_raise
    batch = WebCrawlerAPI::BatchScrapeResponse.new("status" => "completed")
    assert_nil batch.next
    assert_nil batch.data
    assert_raises(NoMethodError) { batch.nxet }
    assert_nil WebCrawlerAPI::ScrapeResponse.new("status" => "error").markdown
  end
end
