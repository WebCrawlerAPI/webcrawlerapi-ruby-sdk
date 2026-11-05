# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require "json"
require "webcrawlerapi"

WebMock.disable_net_connect!

module TestHelpers
  BASE = "https://api.webcrawlerapi.com"

  def client(**opts)
    @sleeps = []
    WebCrawlerAPI::Client.new("test-key", sleeper: ->(s) { @sleeps << s }, **opts)
  end

  # Accepts a hash or brace-less string-key pairs; `status:` is reserved.
  def json_response(body = {}, status: 200, **fields)
    { status: status, body: JSON.generate(body.merge(fields)), headers: { "Content-Type" => "application/json" } }
  end
end
