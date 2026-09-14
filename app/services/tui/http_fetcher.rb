# frozen_string_literal: true

module Tui
  # Handles HTTP-based fetching with pagination (legacy fallback).
  class HttpFetcher
    def initialize(agency:, page: 1, http_timeout: 15)
      @agency = agency
      @page = page.to_i
      @http_timeout = http_timeout
    end

    def call
      return nil if @page <= 0

      url = build_page_url(@agency, @page)
      return nil if url.blank?

      html, error = fetch_html(url)
      return nil if error || html.blank?

      html
    end

    private

    def build_page_url(agency, page)
      return agency.url if page == 1
      return nil if agency.next_page_url.blank?

      base = agency.next_page_url.to_s
      absolute_base = begin
        base =~ %r{^https?://}i ? base : URI.join(agency.url, base).to_s
      rescue StandardError
        agency.url.to_s + base.to_s
      end

      if absolute_base.match?(/\d+$/)
        absolute_base.sub(/\d+$/, page.to_s)
      else
        absolute_base + page.to_s
      end
    end

    def fetch_html(url)
      conn = Faraday.new do |f|
        f.options.timeout = @http_timeout
        f.options.open_timeout = 8
        f.adapter Faraday.default_adapter
      end
      response = conn.get(url)
      if response.success?
        raw = response.body.to_s
        max_len = 500_000
        html = raw.bytesize > max_len ? raw.byteslice(0, max_len) + "\n<!-- truncated -->" : raw
        [html, nil]
      else
        [nil, "status=#{response.status}"]
      end
    rescue StandardError => e
      [nil, e.message]
    end
  end
end
