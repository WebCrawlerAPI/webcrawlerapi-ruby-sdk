# frozen_string_literal: true

require_relative "lib/webcrawlerapi/version"

Gem::Specification.new do |spec|
  spec.name          = "webcrawlerapi"
  spec.version       = WebCrawlerAPI::VERSION
  spec.authors       = ["WebcrawlerAPI"]
  spec.email         = ["sdk@webcrawlerapi.com"]

  spec.summary       = "Ruby client for WebcrawlerAPI"
  spec.description   = "Crawl and scrape websites, convert pages to markdown and run AI agents with WebcrawlerAPI."
  spec.homepage      = "https://webcrawlerapi.com"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => "https://github.com/WebCrawlerAPI/webcrawlerapi-ruby-sdk",
    "changelog_uri"         => "https://github.com/WebCrawlerAPI/webcrawlerapi-ruby-sdk/blob/main/CHANGELOG.md",
    "documentation_uri"     => "https://webcrawlerapi.com/docs",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.19"
end
