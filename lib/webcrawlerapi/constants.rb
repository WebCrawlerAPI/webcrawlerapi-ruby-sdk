# frozen_string_literal: true

module WebCrawlerAPI
  module JobStatus
    IN_PROGRESS = "in_progress"
    NEW = "new"
    DONE = "done"
  end

  module ErrorCode
    BLOCKED_BY_ROBOTS_TXT = "blocked_by_robots_txt"
  end

  BASE_PATH = "https://api.webcrawlerapi.com"
  SCRAPE_VERSION = "v2"
  INITIAL_PULL_DELAY_SECONDS = 2.0
  MAX_PULL_RETRIES = 100
  DEFAULT_POLL_DELAY_SECONDS = 2.0
  SCRAPE_MAX_WAIT_SECONDS = 400.0
  # Effectively unbounded by count at the 2s default; elapsed time is the real limit.
  SCRAPE_MAX_POLLS = 1000
  BATCH_SCRAPING_STATUS = "scraping"
  AGENT_TERMINAL_STATUSES = %w[done error canceled].freeze
end
