# frozen_string_literal: true

module TravelAgencies
  # Sequentially fetches TUI offers page-by-page. Stops when:
  # 1) no offers parsed; 2) fetch error; 3) travel agency missing; 4) optional max_pages exceeded.
  # This emulates clicking the "Show more" button by requesting the next page URL pattern.
  class TuiSequentialFetchJob < ApplicationJob
    queue_as :default

    # @param travel_agency_id [Integer]
    # @param page [Integer]
    # @param query [String, nil]
    # @param max_pages [Integer, nil] if nil => unlimited until no offers or error
    def perform(page: 1, query: nil, max_pages: 100)
      agency = ::TravelAgency.find_by(name_id: 'tui')
      return unless agency

      # Prefer browser-driven flow if Ferrum is available; fallback to legacy HTTP pagination
      if ferrum_available?
        perform_with_browser(agency, query: query, max_pages: max_pages)
        return
      end

      legacy_perform_http(agency, page: page, query: query, max_pages: max_pages)
    end

    private

    def ferrum_available?
      require 'ferrum'
      true
    rescue LoadError
      false
    end

    def new_browser(timeout: 25)
      require 'ferrum'
      flags = { 'headless': true }
      if ENV['FERRUM_NO_SANDBOX'] == '1'
        flags[:'no-sandbox'] = nil
        flags[:'disable-gpu'] = nil
      end
      kwargs = { timeout: timeout, browser_options: flags }
      kwargs[:path] = ENV['FERRUM_BROWSER_PATH'] if ENV['FERRUM_BROWSER_PATH'].present?
      Ferrum::Browser.new(**kwargs)
    end

    def perform_with_browser(agency, query:, max_pages:)
      browser = new_browser(timeout: 25)
      begin
        browser.goto(agency.url)
        wait_for_idle_and_offers(browser, timeout: 20)

        day_index = -1
        loop do
          day_index += 1
          break unless click_day_tile(browser, day_index)
          wait_for_idle_and_offers(browser, timeout: 20)

          # First batch for the selected day
          persist_batch(browser, agency, query)

          # Click "Pokaż więcej" repeatedly until no more offers for the day
          clicks = 0
          while click_load_more(browser)
            clicks += 1
            wait_for_idle_and_offers(browser, timeout: 20)
            persist_batch(browser, agency, query)
            break if max_pages && clicks >= max_pages
          end
        end
      ensure
        browser&.quit
      end
    end

    def click_day_tile(browser, index)
      tiles = browser.css('div.upcoming-offers-tile')
      return false if tiles.nil? || tiles.empty?
      node = tiles[index]
      return false unless node
      begin
        node.scroll_into_view
      rescue StandardError
      end
      node.click
      true
    rescue StandardError
      false
    end

    def click_load_more(browser)
      # Find span with text "Pokaż więcej" and click its closest button ancestor if present
      nodes = browser.css('span.button__content')
      return false if nodes.nil? || nodes.empty?
      target = nodes.find { |n| n.text.to_s.strip.downcase.include?('pokaż więcej') }
      return false unless target
      button = target.at_xpath('ancestor::button[1]') rescue nil
      (button || target).click
      true
    rescue StandardError
      false
    end

    def wait_for_idle_and_offers(browser, timeout: 20)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      last_url = nil
      loop do
        begin
          browser.network.wait_for_idle(timeout: 2)
        rescue StandardError
        end
        current = browser.current_url
        last_url = current if last_url.nil?
        before = browser.css(::TuiScraper::OFFER_CONTAINER_SELECTOR)&.count || 0
        sleep 0.3
        after  = browser.css(::TuiScraper::OFFER_CONTAINER_SELECTOR)&.count || 0
        url_stable = (current == last_url)
        offers_ready = (after > 0) && (before == after)
        break if url_stable && offers_ready
        last_url = current
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      end
    end

    def persist_batch(browser, agency, query)
      html = browser.body
      base = browser.current_url
      offers = ::TuiScraper.new(base_url: base, use_browser: false).call(html: html)
      offers.select! { |o| o[:name].to_s.downcase.include?(query.to_s.downcase) } if query.present?
      return if offers.blank?
      persist_countries_hotels_offers(agency, offers)
    end

    # Legacy HTTP flow retained as fallback
    def legacy_perform_http(agency, page:, query:, max_pages:)
      page = page.to_i
      return if page <= 0

      unlimited = max_pages.nil?
      unless unlimited
        return if page > max_pages.to_i
      end

      url = build_page_url(agency, page)
      return if url.blank?

      html, error = fetch_html(url)
      if error || html.blank?
        Rails.logger.info("TuiSequentialFetchJob: fetch error on page=#{page} agency=#{agency.id} error=#{error}")
        return
      end

      offers = ::TuiScraper.new(base_url: agency.url, use_browser: false).call(html: html)
      offers.select! { |o| o[:name].to_s.downcase.include?(query.to_s.downcase) } if query.present?

      if offers.blank?
        Rails.logger.info("TuiSequentialFetchJob: no offers on page=#{page} agency=#{agency.id}, stopping")
        return
      end

      persist_countries_hotels_offers(agency, offers)

      next_page = page.to_i + 1
      unless unlimited
        return if next_page > max_pages.to_i
      end

      if agency.next_page_url.blank?
        Rails.logger.info("TuiSequentialFetchJob: next_page_url blank, stopping after page=#{page} agency=#{agency.id}")
        return
      end

      self.class.perform_later(page: next_page, query: query, max_pages: max_pages)
    end

    def build_page_url(agency, page)
      return agency.url if page == 1
      return nil if agency.next_page_url.blank?

      base = agency.next_page_url.to_s
      # Merge relative path with base url
      absolute_base = begin
        base =~ %r{^https?://}i ? base : URI.join(agency.url, base).to_s
      rescue
        agency.url.to_s + base.to_s
      end

      # If base already ends with a number, replace it with the page; else append page
      if absolute_base.match?(/\d+$/)
        absolute_base.sub(/\d+$/, page.to_s)
      else
        absolute_base + page.to_s
      end
    end

    def fetch_html(url)
      conn = Faraday.new do |f|
        f.options.timeout      = 15
        f.options.open_timeout = 8
        f.adapter Faraday.default_adapter
      end
      response = conn.get(url)
      if response.success?
        raw     = response.body.to_s
        max_len = 500_000
        html    = raw.bytesize > max_len ? raw.byteslice(0, max_len) + "\n<!-- truncated -->" : raw
        [html, nil]
      else
        [nil, "status=#{response.status}"]
      end
    rescue => e
      [nil, e.message]
    end

    def persist_countries_hotels_offers(agency, offers)
      countries_map = {}
      offers.each do |offer|
        # Collect countries from offer (array preferred), fallback to single :country
        countries_list = Array(offer[:countries]).map { |c| c.to_s.strip }.reject(&:empty?)
        countries_list = [offer[:country].to_s.strip].reject(&:empty?) if countries_list.empty? && offer[:country].present?
        countries_list.uniq!

        # Ensure all countries exist in DB and cache them
        resolved_countries = []
        countries_list.each do |cname|
          normalized = ::Country.normalize(cname)
          country_rec = countries_map[normalized] ||= ::Country.where(normalized_name: normalized).first_or_create(name: cname)
          resolved_countries << country_rec
        end
        main_country = resolved_countries.first

        hotel = find_or_initialize_hotel(offer)
        # Attach main country and persist
        save_hotel(hotel, offer, main_country, agency)
        # Also keep all countries on hotel.raw_data for reference
        begin
          rd = (hotel.raw_data || {}).dup
          rd[:countries] = countries_list if countries_list.any?
          hotel.update_column(:raw_data, rd)
        rescue StandardError
        end

        persist_offer_snapshot(hotel, offer, agency)
      end
    end

    def find_or_initialize_hotel(offer)
      if offer[:url].present?
        ::Hotel.where(url: offer[:url]).first_or_initialize
      else
        ::Hotel.where(name: offer[:name]).first_or_initialize
      end
    end

    def save_hotel(hotel, offer, country, agency)
      hotel.name = offer[:name]
      hotel.url = offer[:url] if offer[:url].present?
      hotel.country = country if country
      hotel.image_url = offer[:image_url] if offer[:image_url].present?
      hotel.source_fetched_at = Time.current
      hotel.raw_data = offer
      hotel.travel_agency ||= agency if hotel.respond_to?(:travel_agency) && hotel.travel_agency.nil?
      hotel.save(validate: true)
    rescue ActiveRecord::RecordInvalid
      # ignore invalid hotel
    end

    def persist_offer_snapshot(hotel, offer, agency)
      return unless defined?(::Offer)
      return if hotel.nil? || !hotel.persisted?

      existing = hotel.offers.where(url: offer[:url], starts_on: offer[:starts_on], travel_agency_id: agency.id, price: offer[:price]).order(created_at: :desc).first
      if existing
        return
      end

      record = hotel.offers.build
      record.name = offer[:name]
      record.url = offer[:url]
      record.price = offer[:price]
      record.price_raw = offer[:price_raw]
      record.starts_on = offer[:starts_on]
      record.source_fetched_at = Time.current
      record.raw_data = offer
      record.travel_agency = agency
      record.save(validate: true)
    rescue ActiveRecord::RecordInvalid
      # ignore offer errors
    end
  end
end

