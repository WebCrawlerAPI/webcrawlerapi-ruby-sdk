# WebcrawlerAPI Ruby SDK

Ruby client for [WebcrawlerAPI](https://webcrawlerapi.com). No runtime dependencies, Ruby 3.0+.

## Install

```ruby
gem "webcrawlerapi"
```

or `gem install webcrawlerapi`.

## Usage

```ruby
require "webcrawlerapi"

client = WebCrawlerAPI::Client.new("YOUR_API_KEY")

# Scrape one page (polls until done)
res = client.scrape(url: "https://example.com", output_formats: ["markdown"])
puts res.markdown

# Scrape many URLs: pass an array, polls until the batch finishes.
# Returns the first page of items (`data`) and the `next` cursor.
batch = client.scrape(url: ["https://example.com", "https://example.com/pricing"],
                      output_formats: ["markdown"], max_concurrency: 5)
batch.data.each { |item| puts "#{item['url']} #{item['status']} #{item['markdown_url']}" }
more = client.get_batch(batch.id, cursor: batch.next, limit: 100) unless batch.next.to_s.empty?

# Crawl a site (polls until the job finishes)
job = client.crawl(url: "https://example.com", items_limit: 10)
job.job_items.each do |item|
  puts item.original_url
  puts item.get_content   # markdown by default
end

# Markdown of a single article
puts client.markdown(url: "https://example.com/post").markdown

# Agent
run = client.run_agent(prompt: "Find pricing of example.com", urls: ["https://example.com"], max_spend_usd: 1)
puts run.data
```

## Methods (same as the JS SDK, snake_case)

| JS | Ruby |
|----|------|
| `scrape` / `scrapeAsync` / `getScrape` | `scrape` / `scrape_async` / `get_scrape` |
| `crawl` / `crawlAsync` / `getJob` | `crawl` / `crawl_async` / `get_job` |
| `getJobMarkdown` / `getJobMarkdownContent` | `get_job_markdown` / `get_job_markdown_content` |
| `markdown` | `markdown` |
| `runAgent` / `runAgentAsync` / `getAgentJob` | `run_agent` / `run_agent_async` / `get_agent_job` |
| `item.getContent/getMarkdown/getCleaned/getHTML` | `item.get_content/get_markdown/get_cleaned/get_html` |

Batch scrape: `scrape(url: [...])` (or `scrape_batch`) waits for the batch; `scrape_batch_async`, `get_batch(id, limit:, cursor:)`,
`get_batch_errors(id)` and `cancel_batch(id)` cover the non-waiting flow. Batch-only options: `max_concurrency`,
`ignore_invalid_urls`, `webhook_url`.

Full batch scrape documentation: [docs/batch-scrape.md](docs/batch-scrape.md).

`scrape`, `crawl` and `run_agent` take an optional second argument `max_polls`.
Responses are `WebCrawlerAPI::Model` objects: `res.markdown`, `res[:markdown]` or `res.to_h`.

## Errors

Every failure raises `WebCrawlerAPI::Error` with `error_code`, `error_message`, `status_code`
(`network_error`, `timeout`, `invalid_response` are raised client-side).

```ruby
begin
  client.crawl(url: "https://example.com")
rescue WebCrawlerAPI::Error => e
  warn "#{e.error_code} (#{e.status_code}): #{e.error_message}"
end
```

## Options

```ruby
WebCrawlerAPI::Client.new("KEY", base_path: "https://api.webcrawlerapi.com", api_version: "v1",
                                 open_timeout: 10, read_timeout: 60)
```

## Development

```sh
bundle install
bundle exec rake test
```

MIT license.
