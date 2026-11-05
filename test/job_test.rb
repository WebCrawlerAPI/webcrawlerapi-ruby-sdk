# frozen_string_literal: true

require "test_helper"

class JobTest < Minitest::Test
  include TestHelpers

  def job_payload(overrides = {})
    {
      "id" => "j1", "status" => "done", "output_formats" => ["markdown"],
      "job_items" => [{
        "id" => "i1", "status" => "done",
        "markdown_content_url" => "https://cdn.test/i1.md",
        "cleaned_content_url" => "https://cdn.test/i1.txt",
        "raw_content_url" => "https://cdn.test/i1.html"
      }]
    }.merge(overrides)
  end

  def fetch_job(payload)
    stub_request(:get, "#{BASE}/v1/job/j1").to_return(json_response(payload))
    client.get_job("j1")
  end

  def stub_cdn
    stub_request(:get, "https://cdn.test/i1.md").to_return(body: "MD")
    stub_request(:get, "https://cdn.test/i1.txt").to_return(body: "CLEAN")
    stub_request(:get, "https://cdn.test/i1.html").to_return(body: "HTML")
  end

  def test_job_items_are_wrapped
    item = fetch_job(job_payload).job_items.first
    assert_kind_of WebCrawlerAPI::JobItem, item
    assert_equal "i1", item.id
    assert_equal "i1", item[:id]
  end

  def test_model_to_h_and_respond_to
    job = fetch_job(job_payload)
    assert job.respond_to?(:status)
    refute job.respond_to?(:nonexistent)
    assert_raises(NoMethodError) { job.nonexistent }
    assert_equal "j1", job.to_h["id"]
  end

  def test_get_markdown_cleaned_html
    stub_cdn
    item = fetch_job(job_payload).job_items.first
    assert_equal "MD", item.get_markdown
    assert_equal "CLEAN", item.get_cleaned
    assert_equal "HTML", item.get_html
  end

  def test_get_content_prefers_markdown_then_cleaned_then_html
    stub_cdn
    all = fetch_job(job_payload("output_formats" => %w[html cleaned markdown])).job_items.first
    assert_equal "MD", all.get_content
    cleaned = fetch_job(job_payload("output_formats" => %w[html cleaned])).job_items.first
    assert_equal "CLEAN", cleaned.get_content
    html = fetch_job(job_payload("output_formats" => ["html"])).job_items.first
    assert_equal "HTML", html.get_content
  end

  def test_get_content_nil_for_unknown_output_formats
    stub_cdn
    item = fetch_job(job_payload("output_formats" => ["links"])).job_items.first
    assert_nil item.get_content
  end

  def test_get_content_falls_back_to_scrape_type
    stub_cdn
    payload = job_payload("scrape_type" => "cleaned")
    payload.delete("output_formats")
    assert_equal "CLEAN", fetch_job(payload).job_items.first.get_content
  end

  def test_get_content_nil_when_job_or_item_not_done
    stub_cdn
    assert_nil fetch_job(job_payload("status" => "in_progress")).job_items.first.get_content

    payload = job_payload
    payload["job_items"][0]["status"] = "new"
    assert_nil fetch_job(payload).job_items.first.get_content
  end

  def test_missing_url_returns_nil
    payload = job_payload
    payload["job_items"][0].delete("markdown_content_url")
    assert_nil fetch_job(payload).job_items.first.get_markdown
  end

  def test_fetch_failure_raises
    stub_request(:get, "https://cdn.test/i1.md").to_return(status: 403, body: "denied")
    err = assert_raises(WebCrawlerAPI::Error) { fetch_job(job_payload).job_items.first.get_markdown }
    assert_equal "fetch_error", err.error_code
    assert_equal 403, err.status_code
  end

  def test_fetch_network_failure_raises
    stub_request(:get, "https://cdn.test/i1.md").to_raise(SocketError)
    err = assert_raises(WebCrawlerAPI::Error) { fetch_job(job_payload).job_items.first.get_markdown }
    assert_equal "network_error", err.error_code
  end

  def test_job_without_items
    assert_empty fetch_job("id" => "j1", "status" => "done").job_items
  end
end
