# frozen_string_literal: true

require 'nokogiri'
require 'net/http'
require 'uri'
require 'bigdecimal'
require 'ferrum'

class TuiScraper
  OFFER_CONTAINER_SELECTOR = 'div.offer-tile-wrapper.offer-tile-wrapper--listingOffer'
  HOTEL_NAME_SELECTOR      = 'span.offer-tile-body__hotel-name'
  PRICE_SELECTOR           = 'span.price-value__amount, [data-testid="price-amount"]'
  DATE_RANGE_REGEX         = /\b\d{2}\.\d{2}\.\d{4}\s*[-–]\s*\d{2}\.\d{2}\.\d{4}\b/

  def initialize(base_url:, http_timeout: 15, user_agent: default_user_agent, use_browser: true)
    @base_url     = base_url
    @http_timeout = http_timeout
    @user_agent   = user_agent
    @use_browser  = use_browser
  end

  # Returns array of hashes: [{ name:, url:, price:, starts_on:, raw_data: }, ...]
  def call(html: nil)
    doc = html ? Nokogiri::HTML(html) : fetch_document(@base_url)
    parse_offers(doc)
  end

  private

  def default_user_agent
    "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
  end

  def fetch_document(url)
    if @use_browser
      doc = fetch_with_browser(url)
      return doc if doc
    end
    fetch_with_http(url)
  end

  # Headless browser path: follows JS redirects and waits for the final, populated page
  def fetch_with_browser(url)
    browser_flags = { 'headless': true }
    if ENV['FERRUM_NO_SANDBOX'] == '1'
      browser_flags[:'no-sandbox'] = nil
      browser_flags[:'disable-gpu'] = nil
    end

    browser_kwargs = { timeout: @http_timeout, browser_options: browser_flags }
    if ENV['FERRUM_BROWSER_PATH'].present?
      browser_kwargs[:path] = ENV['FERRUM_BROWSER_PATH']
    end

    browser = Ferrum::Browser.new(**browser_kwargs)
    begin
      browser.headers.set({ 'User-Agent' => @user_agent }) rescue nil
      browser.goto(url)

      # Wait until network is idle and URL stabilizes (handles redirects)
      stable_url_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      last_url         = nil
      deadline         = stable_url_since + @http_timeout

      loop do
        begin
          browser.network.wait_for_idle(timeout: 2)
        rescue StandardError
          # ignore short spikes
        end

        current = browser.current_url
        if current != last_url
          last_url = current
          stable_url_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Also wait for the main container to appear and stabilize in count
        before_count = browser.css(OFFER_CONTAINER_SELECTOR)&.count || 0
        sleep 0.3
        after_count  = browser.css(OFFER_CONTAINER_SELECTOR)&.count || 0

        url_stable   = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - stable_url_since) >= 0.8
        count_stable = (before_count > 0) && (before_count == after_count)

        break if (url_stable && count_stable) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      end

      return Nokogiri::HTML(browser.body)
    rescue StandardError
      nil
    ensure
      browser&.quit
    end
  end

  # Pure HTTP path: follows 3xx redirects to the final URL, then returns parsed HTML
  def fetch_with_http(url, limit: 5)
    raise 'too many redirects' if limit <= 0

    uri = URI.parse(url)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = @user_agent

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https',
      read_timeout: @http_timeout,
      open_timeout: @http_timeout
    ) do |http|
      res = http.request(req)

      case res
      when Net::HTTPSuccess
        return Nokogiri::HTML(res.body)
      when Net::HTTPRedirection
        location = res['location']
        raise 'redirect without location header' if location.to_s.empty?
        next_url = begin
          URI.join(url, location).to_s
        rescue
          location
        end
        return fetch_with_http(next_url, limit: limit - 1)
      else
        raise "HTTP error: #{res.code}"
      end
    end
  end

  def parse_offers(doc)
    doc.css(OFFER_CONTAINER_SELECTOR).map { |node| parse_offer(node) }.compact
  end

  def parse_offer(node)
    hotel_name = text_or_nil(node.at_css(HOTEL_NAME_SELECTOR))
    return nil if hotel_name.nil?

    href       = node.at_css('a')&.[]('href')
    url        = absolute_url(href)
    date_str   = node.to_html.scan(DATE_RANGE_REGEX).first
    price_text = text_or_nil(node.at_css(PRICE_SELECTOR))
    price      = to_decimal(price_text)

    {
      name:      hotel_name,
      url:       url,
      price:     price,
      price_raw: price_text,
      starts_on: date_str,
      raw_data:  collect_raw(node)
    }
  end

  def collect_raw(node)
    data_attrs = {}
    node.traverse do |el|
      next unless el.element?
      el.attribute_nodes.each do |attr|
        next unless attr.name.start_with?('data-')
        (data_attrs[attr.name] ||= []) << attr.value
      end
    end
    data_attrs.transform_values!(&:uniq)

    {
      container_classes:   node['class'],
      raw_text:            squish(node.text),
      raw_html:            node.to_html,
      detected_date:       node.to_html.scan(DATE_RANGE_REGEX).first,
      detected_price_text: text_or_nil(node.at_css(PRICE_SELECTOR))
    }.merge(data_attrs)
  end

  def text_or_nil(el)
    return nil unless el
    squish(el.text)
  end

  def squish(str)
    str.to_s.gsub(/\s+/, ' ').strip
  end

  def to_decimal(str)
    return nil if str.to_s.strip.empty?
    s = str.gsub(/[^\d,\.\-]/, '')
    if s.count(',') == 1 && s.count('.') == 0
      s = s.tr(',', '.')
    else
      s = s.gsub(/[[:space:]\u00A0\u202F.]/, '')
    end
    BigDecimal(s)
  rescue ArgumentError
    nil
  end

  def absolute_url(href)
    return nil if href.to_s.empty?
    URI.join(@base_url, href).to_s
  rescue
    href
  end
end
