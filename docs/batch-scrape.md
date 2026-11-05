# Batch scrape (Ruby SDK)

Batch scrape takes an explicit list of URLs and scrapes them in one async request on the API side. No crawling, no per-URL requests. See also the [batch scrape guide](https://webcrawlerapi.com/docs/guides/batch-scrape) and the [API reference](https://webcrawlerapi.com/docs/api/batch-scrape).

The SDK sends the request hash as the JSON body, so every option from the API reference can be passed as a key. Symbol and string keys both work.

## Quick example

```ruby
require "webcrawlerapi"

client = WebCrawlerAPI::Client.new("YOUR_API_KEY")

batch = client.scrape(
  url: ["https://example.com", "https://example.com/pricing"],
  output_formats: ["markdown"],
  max_concurrency: 5
)

puts "#{batch.status}: #{batch.completed}/#{batch.total} done, #{batch.failed} failed"
batch.data.each { |item| puts "#{item['url']} #{item['status']} #{item['markdown_url']}" }
```

`scrape` polls until the batch is no longer `scraping`, then returns the first page of items.

## Request options

Passed in the request hash of `scrape`, `scrape_batch` and `scrape_batch_async`.

| Key | Description |
|-----|-------------|
| `url` (Array) or `urls` | (required) URLs to scrape. Max is your plan's job items limit (100 during trial). |
| `output_formats` | Array: `markdown`, `cleaned`, `html`, `links`, `images`. API default is `["markdown"]`. |
| `main_content_only` | Extract only the main content. API default `false`. |
| `clean_selectors` | CSS selectors to clean from the output. |
| `max_concurrency` | Max URLs scraped in parallel for this batch. `0` or omitted means no per-batch cap. |
| `ignore_invalid_urls` | Skip invalid URLs and report them in `invalid_urls`. If `false`, any invalid URL fails the request with `400`. API default `true`. |
| `webhook_url` | Public http(s) URL called once when the batch finishes. |
| `max_age` | Cache duration in seconds. API default `604800` (7 days); `0` bypasses the cache. |
| `respect_robots_txt` | Respect each website's robots.txt. API default `false`. |

`prompt`, `response_schema` and `actions` are not supported in batch scrape.

URLs are normalized and deduplicated. Duplicates and rejected URLs come back in `invalid_urls` with `error_code` and `error_message`.

## Methods

### `scrape(request, max_polls = SCRAPE_MAX_POLLS)`

Returns `ScrapeResponse` for a single URL, or `BatchScrapeResponse` when `request[:url]` (or `request["url"]`) is an Array. In the Array case it calls `scrape_batch`.

### `scrape_batch(request, max_polls = SCRAPE_MAX_POLLS)`

Returns `BatchScrapeResponse`. Creates the batch with `scrape_batch_async`, then calls `get_batch` until `status` is not `scraping`, sleeping 2 seconds (`DEFAULT_POLL_DELAY_SECONDS`) between polls. Returns the first page of items and the `next` cursor.

- `max_polls` defaults to `1000`.
- Raises `WebCrawlerAPI::Error` with `error_code` `timeout` if the batch is still `scraping` after `max_polls` polls. The batch keeps running on the API side; use the id from `scrape_batch_async` to continue with `get_batch`.
- Raises `invalid_response` if the API returned no batch id.
- Any API or network error is raised as `WebCrawlerAPI::Error`.

```ruby
batch = client.scrape_batch({ url: urls, output_formats: ["markdown"] }, 200)
```

### `scrape_batch_async(request)`

Returns `BatchScrapeId` (`POST /v2/batch/scrape`) with:

- `id` - batch id
- `status_url` - URL of the status endpoint
- `invalid_urls` - rejected URLs, each with `url`, `error_code`, `error_message`

The URL list is taken from `url` (if it is an Array) or from `urls`.

```ruby
started = client.scrape_batch_async(urls: urls, webhook_url: "https://your-server.com/webhook")
puts started.id
started.invalid_urls.each { |u| puts "#{u['url']}: #{u['error_code']}" }
```

### `get_batch(batch_id, limit: nil, cursor: nil)`

Returns `BatchScrapeResponse` (`GET /v2/batch/scrape/:id`): progress plus one page of items.

- `limit` - items per page, 1 to 500 (API default 100).
- `cursor` - the `next` value of the previous page.

Fields: `id`, `status` (`scraping`, `completed`, `failed` or `cancelled`), `total`, `completed`, `failed`, `canceled`, `data`, `next`.

Each `data` item has `url`, `status` (for example `done` or `error`), and for finished items `page_status_code`, `title`, and `markdown_url` / `cleaned_url` / `html_url` for the requested formats. `from_cache` is `true` for cached results. Failed items have `error_code` and `error_message`. See [Errors](https://webcrawlerapi.com/docs/errors).

```ruby
status = client.get_batch(batch_id)
puts "#{status.completed}/#{status.total}"
```

### `get_batch_errors(batch_id)`

Returns `BatchScrapeErrors` (`GET /v2/batch/scrape/:id/errors`):

- `errors` - failed URLs with `url`, `error_code`, `error_message`
- `robots_blocked` - URLs blocked by robots.txt (when `respect_robots_txt` is `true`)

```ruby
errs = client.get_batch_errors(batch_id)
errs.errors.each { |e| puts "#{e['url']} #{e['error_code']}" }
```

### `cancel_batch(batch_id)`

Returns a `Model` (`DELETE /v2/batch/scrape/:id`), `{"status" => "canceled"}` on success. Items that did not start are marked `canceled` and are not charged. The API answers `400` if the batch already finished, which is raised as `WebCrawlerAPI::Error`.

```ruby
client.cancel_batch(batch_id)
```

## Pagination

`scrape`/`scrape_batch` return only the first page. When `next` is not empty, pass it as `cursor` until `next` is empty:

```ruby
page = batch
items = page.data.dup
until page.next.to_s.empty?
  page = client.get_batch(batch.id, cursor: page.next, limit: 500)
  items.concat(page.data)
end
```

## Polling vs webhook

- Polling: `scrape` / `scrape_batch` wait for you, or call `scrape_batch_async` and then `get_batch` yourself. Poll every few seconds, not faster.
- Webhook: pass `webhook_url` to `scrape_batch_async`. The API sends one `POST` with the same body as `GET /v2/batch/scrape/:id` (first 100 items) when the batch finishes. Fetch the rest with `get_batch(id, cursor:)`.

## Errors

All failures raise `WebCrawlerAPI::Error` with `error_code`, `error_message` and `status_code`. API errors carry the API status code (`400` invalid parameters or no valid URLs, `401`, `402`, `403`, `404`, `500`). Client-side codes: `network_error`, `invalid_response`, `timeout`.

Failed pages do not raise: the batch still finishes, and failures appear as items with `status` `error` and in `get_batch_errors`. Resubmit failed URLs in a new batch to retry them.
