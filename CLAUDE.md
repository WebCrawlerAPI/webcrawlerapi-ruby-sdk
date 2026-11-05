Ruby SDK for WebCrawlerAPI, port of `../../js/webcrawlerapi-js-sdk`. Keep method parity with the JS SDK (snake_case names).
No runtime deps (stdlib net/http). Tests: `bundle install && bundle exec rake test` (minitest + webmock, no real API).
System ruby is 2.6: use `/opt/homebrew/opt/ruby/bin` (3.4) first in PATH.
Publish: `bundle exec rake release` (tags vX.Y.Z, pushes, `gem push` to rubygems.org; needs MFA).
