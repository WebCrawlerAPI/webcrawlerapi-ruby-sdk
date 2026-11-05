# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  include TestHelpers

  def test_requires_api_key
    assert_raises(ArgumentError) { WebCrawlerAPI::Client.new("") }
    assert_raises(ArgumentError) { WebCrawlerAPI::Client.new(nil) }
  end

  def test_sends_auth_and_user_agent_headers
    stub = stub_request(:post, "#{BASE}/markdown")
           .with(headers: { "Authorization" => "Bearer test-key",
                            "User-Agent" => "WebcrawlerAPI-Ruby-Client/#{WebCrawlerAPI::VERSION}",
                            "Content-Type" => "application/json" },
                 body: { url: "https://a.com" }.to_json)
           .to_return(json_response("success" => true, "markdown" => "# hi"))

    res = client.markdown(url: "https://a.com")

    assert_requested stub
    assert res.success
    assert_equal "# hi", res.markdown
  end

  def test_custom_base_path_and_trailing_slash
    stub = stub_request(:post, "http://localhost:9/markdown").to_return(json_response("success" => true))
    WebCrawlerAPI::Client.new("k", base_path: "http://localhost:9/").markdown(url: "x")
    assert_requested stub
  end

  # ---- errors ----

  def test_api_error_is_parsed
    stub_request(:post, "#{BASE}/markdown")
      .to_return(json_response({ "error_code" => "invalid_url", "error_message" => "bad url" }, status: 400))

    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "invalid_url", err.error_code
    assert_equal "bad url", err.error_message
    assert_equal "bad url", err.message
    assert_equal 400, err.status_code
  end

  def test_error_falls_back_to_error_field
    stub_request(:post, "#{BASE}/markdown").to_return(json_response({ "error" => "boom" }, status: 500))
    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "unknown_error", err.error_code
    assert_equal "boom", err.error_message
  end

  def test_non_json_error_body
    stub_request(:post, "#{BASE}/markdown").to_return(status: 502, body: "<html>bad gateway</html>")
    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "unknown_error", err.error_code
    assert_equal 502, err.status_code
  end

  def test_network_error
    stub_request(:post, "#{BASE}/markdown").to_raise(Errno::ECONNREFUSED)
    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "network_error", err.error_code
    assert_equal 0, err.status_code
  end

  def test_timeout_is_network_error
    stub_request(:post, "#{BASE}/markdown").to_timeout
    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "network_error", err.error_code
  end

  def test_invalid_json_success_body
    stub_request(:post, "#{BASE}/markdown").to_return(status: 200, body: "nope")
    err = assert_raises(WebCrawlerAPI::Error) { client.markdown(url: "x") }
    assert_equal "invalid_response", err.error_code
  end

  # ---- scrape ----

  def test_scrape_async
    stub = stub_request(:post, "#{BASE}/v2/scrape?async=true")
           .with(body: { url: "https://a.com", output_formats: ["markdown"] }.to_json)
           .to_return(json_response("id" => "s1"))

    id = client.scrape_async(url: "https://a.com", output_formats: ["markdown"])

    assert_requested stub
    assert_equal "s1", id.id
  end

  def test_get_scrape_done_returns_payload
    stub_request(:get, "#{BASE}/v2/scrape/s1")
      .with(headers: { "Cache-Control" => "no-cache, no-store, must-revalidate" })
      .to_return(json_response("status" => "done", "success" => true, "markdown" => "# x", "page_status_code" => 200))

    res = client.get_scrape("s1")
    assert_equal "done", res.status
    assert_equal "# x", res.markdown
  end

  def test_get_scrape_in_progress_placeholder
    stub_request(:get, "#{BASE}/v2/scrape/s1")
      .to_return(json_response("status" => "in_progress", "recommended_pull_delay_ms" => 500))

    res = client.get_scrape("s1")
    assert_equal false, res.success
    assert_equal "in_progress", res.status
    assert_equal 0, res.page_status_code
    assert_equal 500, res.recommended_pull_delay_ms
  end

  def test_scrape_polls_until_done_and_honors_recommended_delay
    stub_request(:post, "#{BASE}/v2/scrape?async=true").to_return(json_response("id" => "s1"))
    stub_request(:get, "#{BASE}/v2/scrape/s1").to_return(
      json_response("status" => "in_progress", "recommended_pull_delay_ms" => 500),
      json_response("status" => "in_progress"),
      json_response("status" => "done", "success" => true, "markdown" => "ok", "page_status_code" => 200)
    )

    res = client.scrape(url: "https://a.com")

    assert_equal "ok", res.markdown
    assert_equal [0.5, 2.0], @sleeps
  end

  def test_scrape_returns_error_payload_immediately
    stub_request(:post, "#{BASE}/v2/scrape?async=true").to_return(json_response("id" => "s1"))
    stub_request(:get, "#{BASE}/v2/scrape/s1").to_return(
      json_response("status" => "error", "success" => false, "error_code" => "blocked_by_robots_txt",
                    "error_message" => "nope")
    )

    res = client.scrape(url: "https://a.com")

    assert_equal WebCrawlerAPI::ErrorCode::BLOCKED_BY_ROBOTS_TXT, res.error_code
    assert_empty @sleeps
  end

  def test_scrape_returns_last_state_when_max_polls_reached
    stub_request(:post, "#{BASE}/v2/scrape?async=true").to_return(json_response("id" => "s1"))
    stub_request(:get, "#{BASE}/v2/scrape/s1").to_return(json_response("status" => "in_progress"))

    res = client.scrape({ url: "https://a.com" }, 3)

    assert_equal "in_progress", res.status
    assert_equal 3, @sleeps.size
    assert_requested :get, "#{BASE}/v2/scrape/s1", times: 3
  end

  # ---- crawl ----

  def test_crawl_async_defaults_output_formats_to_markdown
    stub = stub_request(:post, "#{BASE}/v1/crawl")
           .with(body: { output_formats: ["markdown"], url: "https://a.com", items_limit: 5 }.to_json)
           .to_return(json_response("id" => "j1"))

    assert_equal "j1", client.crawl_async(url: "https://a.com", items_limit: 5).id
    assert_requested stub
  end

  def test_crawl_async_request_overrides_output_formats
    stub = stub_request(:post, "#{BASE}/v1/crawl")
           .with(body: { output_formats: ["html"], url: "https://a.com" }.to_json)
           .to_return(json_response("id" => "j1"))

    client.crawl_async(url: "https://a.com", output_formats: ["html"])
    assert_requested stub
  end

  def test_crawl_polls_until_job_finished
    stub_request(:post, "#{BASE}/v1/crawl").to_return(json_response("id" => "j1"))
    stub_request(:get, "#{BASE}/v1/job/j1").to_return(
      json_response("id" => "j1", "status" => "new", "recommended_pull_delay_ms" => 3000),
      json_response("id" => "j1", "status" => "in_progress", "recommended_pull_delay_ms" => 0),
      json_response("id" => "j1", "status" => "done", "job_items" => [])
    )

    job = client.crawl(url: "https://a.com")

    assert_equal "done", job.status
    assert_equal [2.0, 3.0, 3.0], @sleeps
  end

  def test_crawl_times_out
    stub_request(:post, "#{BASE}/v1/crawl").to_return(json_response("id" => "j1"))
    stub_request(:get, "#{BASE}/v1/job/j1").to_return(json_response("id" => "j1", "status" => "in_progress"))

    err = assert_raises(WebCrawlerAPI::Error) { client.crawl({ url: "https://a.com" }, 2) }
    assert_equal "timeout", err.error_code
  end

  def test_crawl_empty_job_id
    stub_request(:post, "#{BASE}/v1/crawl").to_return(json_response("id" => ""))
    err = assert_raises(WebCrawlerAPI::Error) { client.crawl(url: "https://a.com") }
    assert_equal "invalid_response", err.error_code
  end

  def test_custom_api_version
    stub = stub_request(:get, "#{BASE}/v2/job/j1").to_return(json_response("id" => "j1", "status" => "done"))
    client(api_version: "v2").get_job("j1")
    assert_requested stub
  end

  # ---- job markdown ----

  def test_get_job_markdown
    stub_request(:get, "#{BASE}/v1/job/j1/markdown").to_return(json_response("content_url" => "https://c/x.md"))
    assert_equal "https://c/x.md", client.get_job_markdown("j1").content_url
  end

  def test_get_job_markdown_content_returns_raw_text
    stub_request(:get, "#{BASE}/v1/job/j1/markdown/content").to_return(status: 200, body: "# Title\n\nBody")
    assert_equal "# Title\n\nBody", client.get_job_markdown_content("j1")
  end

  def test_get_job_markdown_content_error
    stub_request(:get, "#{BASE}/v1/job/j1/markdown/content")
      .to_return(json_response({ "error_code" => "not_found", "error_message" => "no job" }, status: 404))
    err = assert_raises(WebCrawlerAPI::Error) { client.get_job_markdown_content("j1") }
    assert_equal 404, err.status_code
    assert_equal "not_found", err.error_code
  end

  # ---- agent ----

  def test_run_agent_async
    stub = stub_request(:post, "#{BASE}/v1/agent")
           .with(body: { prompt: "find", max_spend_usd: 1 }.to_json)
           .to_return(json_response("id" => "a1", "status" => "new"))

    run = client.run_agent_async(prompt: "find", max_spend_usd: 1)
    assert_requested stub
    assert_equal "a1", run.id
  end

  def test_get_agent_job
    stub_request(:get, "#{BASE}/v1/agent/job/a1").to_return(json_response("id" => "a1", "status" => "done"))
    assert_equal "done", client.get_agent_job("a1").status
  end

  def test_run_agent_returns_immediately_when_terminal
    stub_request(:post, "#{BASE}/v1/agent").to_return(json_response("id" => "a1", "status" => "done", "data" => { "x" => 1 }))
    run = client.run_agent(prompt: "p", max_spend_usd: 1)
    assert_equal({ "x" => 1 }, run.data)
    assert_empty @sleeps
  end

  def test_run_agent_polls_until_terminal
    stub_request(:post, "#{BASE}/v1/agent").to_return(json_response("id" => "a1", "status" => "new"))
    stub_request(:get, %r{#{BASE}/v1/agent/job/a1\?t=\d+}).to_return(
      json_response("id" => "a1", "status" => "in_progress"),
      json_response("id" => "a1", "status" => "canceled")
    )

    run = client.run_agent(prompt: "p", max_spend_usd: 1)

    assert_equal "canceled", run.status
    assert_equal [2.0, 2.0], @sleeps
  end

  def test_run_agent_times_out
    stub_request(:post, "#{BASE}/v1/agent").to_return(json_response("id" => "a1", "status" => "new"))
    stub_request(:get, %r{#{BASE}/v1/agent/job/a1}).to_return(json_response("id" => "a1", "status" => "in_progress"))

    err = assert_raises(WebCrawlerAPI::Error) { client.run_agent({ prompt: "p", max_spend_usd: 1 }, 2) }
    assert_equal "timeout", err.error_code
  end
end
