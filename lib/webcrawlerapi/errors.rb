# frozen_string_literal: true

module WebCrawlerAPI
  # Raised for every API, network and polling failure.
  class Error < StandardError
    attr_reader :error_code, :error_message, :status_code

    def initialize(error_code, error_message, status_code = nil)
      super(error_message)
      @error_code = error_code
      @error_message = error_message
      @status_code = status_code
    end

    # Builds an error from a parsed API error body (Hash with string keys).
    def self.from_response(status_code, data)
      data = {} unless data.is_a?(Hash)
      new(
        data["error_code"] || "unknown_error",
        data["error_message"] || data["error"] || "Unknown error",
        status_code
      )
    end
  end
end
