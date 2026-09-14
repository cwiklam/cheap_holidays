# frozen_string_literal: true

module Tui
  # Handles browser-driven fetching using Ferrum (Chromium headless).
  # Clicks through day tiles and "Pokaż więcej" buttons to paginate.
  class BrowserFetcher
    def initialize(base_url:, timeout: 25, offer_selector: nil)
      @base_url = base_url
      @timeout = timeout
      @offer_selector = offer_selector || ::Tui::Scraper::OFFER_CONTAINER_SELECTOR
    end

    def call
      browser = new_browser(timeout: @timeout)
      begin
        browser.goto(@base_url)
        handle_cookiebot(browser)
        wait_for_idle_and_offers(browser, timeout: 20)

        html_batches = []
        day_index = -1
        loop do
          day_index += 1
          break unless click_day_tile(browser, day_index)
          handle_cookiebot(browser)
          wait_for_idle_and_offers(browser, timeout: 20)

          html_batches << browser.body

          # Click "Pokaż więcej" repeatedly until no more offers for the day
          while click_load_more(browser)
            handle_cookiebot(browser)
            wait_for_idle_and_offers(browser, timeout: 20)
            html_batches << browser.body
          end
        end

        html_batches
      ensure
        browser&.quit
      end
    end

    private

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

    def handle_cookiebot(browser)
      wrappers = browser.css('div.CybotCookiebotDialogContentWrapper')
      return if wrappers.nil? || wrappers.empty?

      wrapper = wrappers.first
      candidates = []
      begin
        candidates.concat(wrapper.css('button'))
      rescue StandardError
      end

      button = candidates.find do |node|
        text = node.text.to_s.strip.downcase
        text.include?('reject') ||
          text.include?('decline') ||
          text.include?('tylko niezbędne') ||
          text.include?('tylko konieczne') ||
          text.include?('use necessary') ||
          text.include?('necessary only')
      end

      button ||= candidates.find do |node|
        txt = node.text.to_s.strip
        txt == '×' || txt == 'x'
      end

      button ||= candidates.first

      return unless button

      begin
        button.scroll_into_view
      rescue StandardError
      end

      begin
        button.click
      rescue StandardError
      end
    rescue StandardError
      nil
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
        before = browser.css(@offer_selector)&.count || 0
        sleep 0.3
        after = browser.css(@offer_selector)&.count || 0
        url_stable = (current == last_url)
        offers_ready = (after > 0) && (before == after)
        break if url_stable && offers_ready
        last_url = current
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      end
    end
  end
end
