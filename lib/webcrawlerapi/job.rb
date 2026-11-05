# frozen_string_literal: true

require "net/http"
require "uri"

module WebCrawlerAPI
  class JobItem < Model
    def initialize(attributes, job)
      super(attributes)
      @job = job
    end

    # Content in the job's preferred format (markdown > cleaned > html). nil unless job and item are done.
    def get_content
      return nil unless @job[:status] == JobStatus::DONE && self[:status] == JobStatus::DONE

      ContentFetcher.fetch(@job.resolve_content_url(self))
    end

    def get_markdown
      ContentFetcher.fetch(self[:markdown_content_url])
    end

    def get_cleaned
      ContentFetcher.fetch(self[:cleaned_content_url])
    end

    def get_html
      ContentFetcher.fetch(self[:raw_content_url])
    end
  end

  class Job < Model
    CONTENT_PRIORITY = [
      ["markdown", :markdown_content_url],
      ["cleaned", :cleaned_content_url],
      ["html", :raw_content_url]
    ].freeze

    SCRAPE_TYPE_URLS = {
      "html" => :raw_content_url,
      "cleaned" => :cleaned_content_url,
      "markdown" => :markdown_content_url
    }.freeze

    def job_items
      @job_items ||= Array(self["job_items"]).map { |item| JobItem.new(item, self) }
    end

    # @api private
    def resolve_content_url(item)
      formats = self[:output_formats]
      if formats.is_a?(Array) && !formats.empty?
        fmt, reader = CONTENT_PRIORITY.find { |name, _| formats.include?(name) }
        return fmt ? item[reader] : nil
      end

      reader = SCRAPE_TYPE_URLS[self["scrape_type"]]
      reader && item[reader]
    end
  end

  # @api private
  module ContentFetcher
    def self.fetch(url)
      return nil if url.nil? || url.to_s.empty?

      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri, "Accept" => "*/*"))
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise Error.new("fetch_error", "Failed to fetch content: #{response.message}", response.code.to_i)
      end

      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    rescue SystemCallError, SocketError, Timeout::Error, IOError, OpenSSL::SSL::SSLError => e
      raise Error.new("network_error", "Failed to fetch content: #{e.message}", 0)
    end
  end
end
