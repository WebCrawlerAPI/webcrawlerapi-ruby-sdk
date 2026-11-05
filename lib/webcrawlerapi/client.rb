# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module WebCrawlerAPI
  class Client
    NO_CACHE_HEADERS = {
      "Cache-Control" => "no-cache, no-store, must-revalidate",
      "Pragma" => "no-cache",
      "Expires" => "0"
    }.freeze

    # @param api_key [String]
    # @param base_path [String]
    # @param api_version [String]
    # @param open_timeout [Numeric] seconds
    # @param read_timeout [Numeric] seconds
    # @param sleeper [#call] called with seconds to wait between polls (override in tests)
    def initialize(api_key, base_path: BASE_PATH, api_version: "v1", open_timeout: 10, read_timeout: 60,
                   sleeper: Kernel.method(:sleep))
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.to_s.strip.empty?

      @api_key = api_key
      @base_path = base_path.to_s.chomp("/")
      @api_version = api_version
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @sleeper = sleeper
    end

    # ---- Scrape -----------------------------------------------------------

    # Starts a scrape and returns its id.
    # @return [ScrapeId]
    def scrape_async(request)
      data = send_request(:post, "#{@base_path}/#{SCRAPE_VERSION}/scrape?async=true", body: request)
      ScrapeId.new("id" => data["id"])
    end

    # Returns the scrape result when done/error, otherwise an in-progress placeholder.
    # @return [ScrapeResponse]
    def get_scrape(scrape_id)
      data = send_request(:get, "#{@base_path}/#{SCRAPE_VERSION}/scrape/#{scrape_id}", no_cache: true)
      status = data["status"]
      return ScrapeResponse.new(data) if %w[done error].include?(status)

      ScrapeResponse.new(
        "success" => false,
        "status" => status,
        "page_status_code" => 0,
        "recommended_pull_delay_ms" => data["recommended_pull_delay_ms"]
      )
    end

    # Starts a scrape and polls until done, error or timeout. Returns the last known state on timeout.
    #
    # If +request[:url]+ is an Array of URLs this creates a batch scrape instead (see #scrape_batch_async),
    # polls until the batch leaves +scraping+ and returns the first page of items plus the +next+ cursor
    # (use #get_batch with +cursor:+ for more). Raises a +timeout+ Error if the batch is still running
    # after +max_polls+ polls. Batch-only options (+max_concurrency+, +webhook_url+, +ignore_invalid_urls+)
    # go in the same request hash.
    # @return [ScrapeResponse, BatchScrapeResponse]
    def scrape(request, max_polls = SCRAPE_MAX_POLLS)
      return scrape_batch(request, max_polls) if request[:url].is_a?(Array) || request["url"].is_a?(Array)

      scrape_id = scrape_async(request)[:id]
      started = monotonic_now
      polls = 0
      result = nil

      while polls < max_polls && monotonic_now - started < SCRAPE_MAX_WAIT_SECONDS
        result = get_scrape(scrape_id)
        return result if %w[done error].include?(result[:status]) || result.key?(:error_code)

        recommended = result[:recommended_pull_delay_ms]
        delay = recommended.to_f.positive? ? recommended / 1000.0 : DEFAULT_POLL_DELAY_SECONDS
        remaining = SCRAPE_MAX_WAIT_SECONDS - (monotonic_now - started)
        break if remaining <= 0

        @sleeper.call([delay, remaining].min)
        polls += 1
      end

      result
    end

    # ---- Batch scrape -----------------------------------------------------

    # Creates a batch scrape (POST /v2/batch/scrape) and returns +id+, +status_url+ and +invalid_urls+.
    # The URL list is taken from +url+ (Array) or +urls+.
    # @return [BatchScrapeId]
    def scrape_batch_async(request)
      body = stringify_keys(request)
      urls = body.delete("url")
      body["urls"] = urls if urls.is_a?(Array)
      BatchScrapeId.new(send_request(:post, "#{@base_path}/#{SCRAPE_VERSION}/batch/scrape", body: body))
    end

    # Returns batch progress and one page of items. +next+ is the cursor for the following page ("" on the last).
    # @param limit [Integer, nil] items per page, 1 to 500
    # @param cursor [String, nil] +next+ value from the previous page
    # @return [BatchScrapeResponse]
    def get_batch(batch_id, limit: nil, cursor: nil)
      query = URI.encode_www_form({ "limit" => limit, "cursor" => cursor }.compact)
      url = "#{@base_path}/#{SCRAPE_VERSION}/batch/scrape/#{batch_id}"
      url += "?#{query}" unless query.empty?
      BatchScrapeResponse.new(send_request(:get, url, no_cache: true))
    end

    # Lists failed URLs (+errors+) and URLs blocked by robots.txt (+robots_blocked+).
    # @return [BatchScrapeErrors]
    def get_batch_errors(batch_id)
      BatchScrapeErrors.new(send_request(:get, "#{@base_path}/#{SCRAPE_VERSION}/batch/scrape/#{batch_id}/errors",
                                         no_cache: true))
    end

    # Cancels a running batch. Returns +{"status" => "canceled"}+.
    # @return [Model]
    def cancel_batch(batch_id)
      Model.new(send_request(:delete, "#{@base_path}/#{SCRAPE_VERSION}/batch/scrape/#{batch_id}"))
    end

    # Creates a batch and polls until it is no longer +scraping+. Same as +scrape(url: [...])+.
    # @return [BatchScrapeResponse]
    def scrape_batch(request, max_polls = SCRAPE_MAX_POLLS)
      batch_id = scrape_batch_async(request)[:id]
      raise Error.new("invalid_response", "Failed to create batch", 0) if batch_id.nil? || batch_id.empty?

      max_polls.times do
        batch = get_batch(batch_id)
        return batch unless batch[:status] == BATCH_SCRAPING_STATUS

        @sleeper.call(DEFAULT_POLL_DELAY_SECONDS)
      end

      raise Error.new("timeout", "Batch scrape took too long, please retry or increase the number of polling retries", 0)
    end

    # ---- Crawl ------------------------------------------------------------

    # Starts a crawl and polls until the job leaves new/in_progress.
    # @return [Job]
    def crawl(request, max_polls = MAX_PULL_RETRIES)
      job_id = crawl_async(request)[:id]
      raise Error.new("invalid_response", "Failed to fetch job status", 0) if job_id.nil? || job_id.empty?

      delay = INITIAL_PULL_DELAY_SECONDS
      max_polls.times do
        @sleeper.call(delay)
        job = get_job(job_id)
        return job unless [JobStatus::IN_PROGRESS, JobStatus::NEW].include?(job[:status])

        delay = job[:recommended_pull_delay_ms] / 1000.0 if job[:recommended_pull_delay_ms].to_i.positive?
      end

      raise Error.new("timeout", "Crawling took too long, please retry or increase the number of polling retries", 0)
    end

    # @return [JobId]
    def crawl_async(request)
      body = { "output_formats" => ["markdown"] }.merge(stringify_keys(request))
      JobId.new(send_request(:post, "#{@base_path}/#{@api_version}/crawl", body: body))
    end

    # @return [Job]
    def get_job(job_id)
      Job.new(send_request(:get, "#{@base_path}/#{@api_version}/job/#{job_id}", no_cache: true))
    end

    # @return [JobMarkdownResponse]
    def get_job_markdown(job_id)
      JobMarkdownResponse.new(send_request(:get, "#{@base_path}/#{@api_version}/job/#{job_id}/markdown", no_cache: true))
    end

    # @return [String]
    def get_job_markdown_content(job_id)
      send_request(:get, "#{@base_path}/#{@api_version}/job/#{job_id}/markdown/content", no_cache: true, raw: true)
    end

    # ---- Markdown ---------------------------------------------------------

    # @return [MarkdownResponse]
    def markdown(request)
      MarkdownResponse.new(send_request(:post, "#{@base_path}/markdown", body: request))
    end

    # ---- Agent ------------------------------------------------------------

    # @return [AgentRun]
    def run_agent_async(request)
      AgentRun.new(send_request(:post, "#{@base_path}/#{@api_version}/agent", body: request))
    end

    # @return [AgentRun]
    def get_agent_job(job_id)
      AgentRun.new(send_request(:get, "#{@base_path}/#{@api_version}/agent/job/#{job_id}", no_cache: true))
    end

    # Runs an agent and polls until done, error or canceled.
    # @return [AgentRun]
    def run_agent(request, max_polls = MAX_PULL_RETRIES)
      run = run_agent_async(request)
      raise Error.new("invalid_response", "Failed to fetch agent job status", 0) if run[:id].nil? || run[:id].empty?
      return run if AGENT_TERMINAL_STATUSES.include?(run[:status])

      max_polls.times do
        @sleeper.call(DEFAULT_POLL_DELAY_SECONDS)
        agent_job = get_agent_job("#{run[:id]}?t=#{(Time.now.to_f * 1000).to_i}")
        return agent_job if AGENT_TERMINAL_STATUSES.include?(agent_job[:status])
      end

      raise Error.new("timeout", "Agent run took too long, please retry or increase the number of polling retries", 0)
    end

    private

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def stringify_keys(hash)
      JSON.parse(JSON.generate(hash))
    end

    def headers(no_cache)
      base = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}",
        "User-Agent" => "WebcrawlerAPI-Ruby-Client/#{VERSION}"
      }
      no_cache ? base.merge(NO_CACHE_HEADERS) : base
    end

    def send_request(method, url, body: nil, no_cache: false, raw: false)
      uri = URI.parse(url)
      klass = { post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method, Net::HTTP::Get)
      req = klass.new(uri, headers(no_cache))
      req.body = JSON.generate(body) if body

      response = begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(req)
        end
      rescue SystemCallError, SocketError, Timeout::Error, IOError, OpenSSL::SSL::SSLError => e
        raise Error.new("network_error", "Failed to send request: #{e.message}", 0)
      end

      raise error_from(response) unless response.is_a?(Net::HTTPSuccess)

      text = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      return text if raw

      JSON.parse(text)
    rescue JSON::ParserError
      raise Error.new("invalid_response", "Response is not valid JSON", response.code.to_i)
    end

    def error_from(response)
      data = JSON.parse(response.body.to_s)
      Error.from_response(response.code.to_i, data)
    rescue JSON::ParserError
      Error.new("unknown_error", "Request failed with status #{response.code} #{response.message}", response.code.to_i)
    end
  end
end
