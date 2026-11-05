# frozen_string_literal: true

module WebCrawlerAPI
  # Thin read-only wrapper over an API JSON object. Fields are available as
  # methods (+job.status+), by key (+job["status"]+ / +job[:status]+) or via +to_h+.
  class Model
    # Declares documented optional fields: readers return nil when the API omits them.
    def self.optional_attributes(*names)
      names.each { |name| define_method(name) { @attributes[name.to_s] } }
    end

    def initialize(attributes)
      @attributes = attributes.is_a?(Hash) ? attributes : {}
    end

    def [](key)
      @attributes[key.to_s]
    end

    def to_h
      @attributes
    end

    def key?(key)
      @attributes.key?(key.to_s)
    end

    def ==(other)
      other.is_a?(self.class) && other.to_h == to_h
    end

    def method_missing(name, *args)
      return super unless args.empty? && @attributes.key?(name.to_s)

      @attributes[name.to_s]
    end

    def respond_to_missing?(name, include_private = false)
      @attributes.key?(name.to_s) || super
    end

    def inspect
      "#<#{self.class.name} #{@attributes.inspect}>"
    end
  end

  class ScrapeResponse < Model
    optional_attributes :success, :status, :markdown, :cleaned_content, :raw_content, :page_status_code,
                        :page_title, :structured_data, :links, :recommended_pull_delay_ms,
                        :error_code, :error_message
  end
  class AgentRun < Model
    optional_attributes :data, :error_reason, :max_spend_usd, :urls
  end
  class MarkdownResponse < Model
    optional_attributes :markdown
  end
  class JobMarkdownResponse < Model; end
  class ScrapeId < Model; end
  class JobId < Model; end
  class BatchScrapeId < Model; end
  class BatchScrapeResponse < Model
    # +next+ is absent on the last page.
    optional_attributes :next, :data
  end
  class BatchScrapeErrors < Model; end
end
