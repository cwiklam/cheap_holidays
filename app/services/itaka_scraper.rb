# frozen_string_literal: true
# OfferScraper: heurystyczne wyciąganie ofert z pobranego HTML strony biura podróży.
# Zwraca tablicę hashy: { title:, price:, currency:, starts_on:, url:, raw_text: }
# Minimalne założenia – można rozszerzać przekazując dodatkowe selektory.
class ItakaScraper
  DEFAULT_SELECTORS = [
    '[data-testid="offer-list-item-button"]',
    '[data-testid="price"]',
    'h3.styles_title__kH0gG',
    '[class*="offer"]',
    '[class*="card"]',
    '[class*="product"]',
    'article',
    'li'
  ].freeze

  PRICE_REGEX = /(?<currency>[$€£]|PLN|EUR|USD)?\s*(?<amount>\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{2})?)/i
  DATE_REGEX = /(\d{4}-\d{2}-\d{2})|(\d{1,2}[\.\/-]\d{1,2}[\.\/-]\d{2,4})/ # prosty heurystyczny wzorzec
  DATE_RANGE_REGEX = /(\d{1,2}\.\d{1,2})(?:\.?(\d{4}))?\s*[\-–]\s*(\d{1,2}\.\d{1,2}\.\d{4})(?:[^\d]*(?:\(|（)\s*(\d+)\s*dni\s*(?:\)|）))?/i
  TITLE_KEYWORDS = %w[hotel resort spa beach aquapark aqua park lake river club].freeze
  TITLE_KEYWORDS_REGEX = /\b(#{TITLE_KEYWORDS.join('|')})\b/i

  def initialize(html, base_url: nil, selectors: DEFAULT_SELECTORS)
    @html = html.to_s
    @base_url = base_url
    @selectors = selectors
    @diagnostics = {
      selectors: selectors,
      candidate_nodes: 0,
      filtered_nodes: 0,
      offers: 0,
      keyword_title_hits: 0,
      price_strategy_hits: Hash.new(0),
      image_alt_hits: 0,
      filtered_missing_keyword: 0,
      filtered_missing_price: 0,
      filtered_missing_term: 0
    }
  end

  def offers
    return [] if @html.start_with?('<!-- fetch') || @html.strip.empty?
    doc = Nokogiri::HTML(@html)
    nodes = candidate_nodes(doc)
    @diagnostics[:candidate_nodes] = nodes.size
    filtered = nodes.select { |n| text_density(n) }
    @diagnostics[:filtered_nodes] = filtered.size
    parsed = filtered.map { |n| extract_offer(n) }.compact
    uniq = {}
    parsed.each do |o|
      key = [o[:name], o[:url]].join('::')
      uniq[key] ||= o
    end
    final = uniq.values
    @diagnostics[:offers] = final.size
    final
  end

  def diagnostics
    @diagnostics
  end

  private

  def candidate_nodes(doc)
    base = @selectors.flat_map { |sel| doc.css(sel) }
    # Podnieś węzeł do rodzica zawierającego nagłówek jeśli sam go nie ma
    expanded = base.map do |n|
      if n.at_css('h1,h2,h3,h4,h5,h6')
        n
      else
        ancestor = n.ancestors.find { |a| a.at_css('h1,h2,h3,h4,h5,h6') }
        ancestor || n
      end
    end
    expanded.uniq
  end

  # text_density teraz uproszczony – logika filtracji przeniesiona nad parserem
  def text_density(node)
    txt = node.text.strip
    txt.length.between?(25, 800) # heurystyka
  end

  def extract_offer(node)
    text = squash(node.text)
    name = extract_title(node, text)
    return nil if name.nil? || name.length < 5

    # Wymóg: nazwa musi zawierać jedno ze słów kluczowych
    unless name =~ TITLE_KEYWORDS_REGEX
      @diagnostics[:filtered_missing_keyword] += 1
      return nil
    end

    anchor = pick_anchor(node)
    link_url = anchor ? absolutize_url(anchor['href']) : nil

    price_data = extract_price_dom(node) || extract_price_regex(text)
    unless price_data
      @diagnostics[:filtered_missing_price] += 1
      return nil
    end

    range_str = extract_date_range(text)
    unless range_str
      date_value = extract_date(text)
      range_str = date_value&.strftime('%Y-%m-%d') if date_value
    end
    unless range_str
      @diagnostics[:filtered_missing_term] += 1
      return nil
    end

    image_url = extract_image_url(node, anchor)
    image_url ||= extract_image_by_alt(node, name)
    country = extract_country(node)

    {
      name: name,
      price: price_data&.dig(:amount),
      price_raw: price_data&.dig(:raw),
      starts_on: range_str,
      url: link_url,
      image_url: image_url,
      country: country
    }
  end

  def extract_title(node, full_text)
    # 1. H nagłówki z anchor i słowem kluczowym
    heading_links = node.css('h1 a, h2 a, h3 a, h4 a, h5 a, h6 a')
    preferred = heading_links.find { |a| a.text =~ TITLE_KEYWORDS_REGEX }
    if preferred
      txt = preferred.text.strip
      @diagnostics[:keyword_title_hits] += 1
      return txt
    end
    # 2. Dowolny nagłówek z keyword
    with_kw = node.css('h1, h2, h3, h4, h5, h6').find { |h| h.text =~ TITLE_KEYWORDS_REGEX }
    if with_kw
      txt = with_kw.text.strip
      @diagnostics[:keyword_title_hits] += 1
      return txt
    end
    # 3. Pierwszy nagłówek jeśli jest (bez keyword)
    any_h = node.at_css('h1, h2, h3, h4, h5, h6')
    return any_h.text.strip if any_h&.text&.strip&.length.to_i >= 5

    lines = full_text.lines.map { |l| l.strip }.reject(&:empty?)
    # Odfiltruj linie ewidentnie cenowe / finansowe
    price_tokens = /(\bzł\b|\/os\.|PLN|EUR|USD|GBP|\d+\s?zł|TFG|TFP)/i
    cleaned = lines.reject { |l| l =~ PRICE_REGEX || l =~ price_tokens }
    # Priorytet linii ze słowem kluczowym
    kw_lines = cleaned.select { |l| l =~ TITLE_KEYWORDS_REGEX }
    unless kw_lines.empty?
      chosen = kw_lines.max_by(&:length)
      @diagnostics[:keyword_title_hits] += 1
      return chosen
    end
    # Fallback: najdłuższa sensowna z oczyszczonych
    cleaned.find { |l| l.length >= 5 }
  end

  def extract_price_dom(node)
    # Preferowane: węzeł z data-testid="current-price" i wartość w podrzędnym span (np. span[data-price-catalog-code], albo klasa zawierająca value)
    container = node.at_css('[data-testid="current-price"]')
    return nil unless container
    value_node = container.at_css('[data-price-catalog-code]') || container.at_css('span[class*="value"]') || container
    raw_text = value_node.text.strip
    # Odfiltruj jeśli tekst nie zawiera wzorca ceny z "zł"
    return nil unless raw_text.match?(/\d+\s?\d*\s*zł/i)
    numeric = raw_text.gsub(/[^0-9]/, '')
    return nil if numeric.empty?
    amount = numeric.to_f
    @diagnostics[:price_strategy_hits][:dom] += 1
    { amount: amount, raw: raw_text }
  end

  def extract_price_regex(text)
    m = text.match(PRICE_REGEX)
    return nil unless m
    amount_str = m[:amount].gsub(/[\s,]/, '').tr(',', '.')
    amount = amount_str.to_f
    # Odtwórz surowy format z ewentualnym sufiksem zł, jeśli występuje w oryginale
    raw_match = text[/\b#{Regexp.escape(m[:amount])}\b[^\n]{0,10}zł/i]
    raw_text = raw_match ? raw_match.strip : m[:amount]
    @diagnostics[:price_strategy_hits][:regex] += 1
    { amount: amount, raw: raw_text }
  end

  def normalize_currency(cur)
    return nil if cur.nil?
    c = cur.strip.upcase
    return 'PLN' if c == 'ZŁ'
    return 'EUR' if c == '€'
    return 'USD' if c == '$'
    return 'GBP' if c == '£'
    c
  end

  def extract_date(text)
    m = text.match(DATE_REGEX)
    return nil unless m
    raw = m[0]
    begin
      # Normalizacja prostych formatów
      cleaned = raw.tr('.', '-').tr('/', '-').split('-').map { |p| p.rjust(2, '0') }.join('-')
      Date.parse(cleaned) rescue nil
    rescue
      nil
    end
  end

  def pick_anchor(node)
    anchors = node.css('a[href]')
    return nil if anchors.empty?
    # Reużycie logiki scoringu z extract_primary_link
    scored = anchors.map do |a|
      href = a['href'].to_s
      score = 0
      score += 70 if href.include?('?id=')
      score += 50 if href.match?(/\/wczasy\//)
      score += 30 if a.text =~ TITLE_KEYWORDS_REGEX
      score += 10 if href.length > 60
      score += 5  if href.count('/') > 3
      { node: a, score: score }
    end
    (scored.max_by { |h| h[:score] })[:node]
  rescue
    nil
  end

  def extract_image_url(node, anchor)
    href = anchor&.[]('href')
    candidates = []
    if href
      # Szukaj globalnie anchor o tym samym href z img
      candidates += node.document.css("a[href='#{href}'] img[data-testid='gallery-img']")
    end
    candidates += node.css('img[data-testid="gallery-img"]')
    img = candidates.find { |i| (i['src'] && !i['src'].empty?) || (i['data-scrollspy'] && !i['data-scrollspy'].empty?) }
    return nil unless img
    src = img['src'].presence || img['data-scrollspy']
    return src if src.start_with?('http://', 'https://') || @base_url.nil?
    absolutize_url(src)
  rescue
    nil
  end

  def extract_image_by_alt(node, name)
    return nil unless name
    name_tokens = name.downcase.split(/[^a-z0-9ąęśćłóżźń]+/i).reject(&:empty?)
    imgs = node.document.css('img[alt]')
    scored = imgs.map do |img|
      alt = img['alt'].to_s.strip
      next if alt.empty?
      alt_down = alt.downcase
      keyword_bonus = TITLE_KEYWORDS.any? { |kw| alt_down.include?(kw) } ? 10 : 0
      overlap = (name_tokens & alt_down.split(/[^a-z0-9ąęśćłóżźń]+/i)).size
      score = overlap * 5 + keyword_bonus - (alt.length - name.length).abs * 0.01
      { img: img, score: score, alt: alt }
    end.compact
    best = scored.max_by { |h| h[:score] }
    return nil unless best && best[:score] > 0
    @diagnostics[:image_alt_hits] += 1
    img = best[:img]
    src = img['src'].presence || img['data-scrollspy']
    return nil unless src
    return src if src.start_with?('http://', 'https://') || @base_url.nil?
    absolutize_url(src)
  rescue
    nil
  end

  def extract_country(node)
    dest = node.at_css('[data-testid="offer-list-item-destination"] a')
    dest&.text&.strip
  end

  def extract_primary_link(node)
    anchors = node.css('a[href]')
    return nil if anchors.empty?

    # 1. Jeśli jest anchor w nagłówku h1-h6 z keyword i parametrem id= lub /wczasy/, bierz go.
    heading_priority = anchors.select do |a|
      parent_h = a.ancestors.find { |anc| anc.name =~ /h[1-6]/ }
      next false unless parent_h
      href = a['href'].to_s
      kw  = a.text =~ TITLE_KEYWORDS_REGEX
      long = href.include?('?id=') || href.match?(/\/wczasy\//)
      kw && long
    end
    unless heading_priority.empty?
      return absolutize_url(heading_priority.first['href'])
    end

    # 2. Anchory z ?id= mają wysoki priorytet.
    scored = anchors.map do |a|
      href = a['href'].to_s
      score = 0
      score += 60 if href.include?('?id=')
      score += 40 if href.match?(/\/wczasy\//)
      score += 25 if a.text =~ TITLE_KEYWORDS_REGEX
      score += 10 if href.length > 60
      score += 5  if href.count('/') > 3
      { node: a, href: href, score: score }
    end

    best = scored.max_by { |h| h[:score] }
    return absolutize_url(best[:href]) if best && best[:score] > 0

    # 3. Fallback: najdłuższy href.
    longest = anchors.max_by { |a| a['href'].to_s.length }
    absolutize_url(longest['href'])
  end

  def absolutize_url(href)
    return nil if href.nil? || href.empty?
    return href if href.start_with?('http://', 'https://') || @base_url.nil?
    URI.join(@base_url, href).to_s
  rescue
    href
  end

  def extract_date_range(text)
    m = text.match(DATE_RANGE_REGEX)
    return nil unless m
    start_raw = m[1]          # np. 9.09 lub 09.09
    start_year = m[2]
    end_raw = m[3]            # np. 17.09.2025
    explicit_days = m[4]

    # Ustal rok końcowy (z end_raw) – wyciągamy
    end_year = end_raw.split('.').last
    year = start_year || end_year

    # Normalizacja start: jeśli brak roku dodajemy ten z końca
    normalized_start = start_raw.include?(year) ? start_raw : "#{start_raw}.#{year}"

    begin
      sd = Date.parse(normalized_start.tr('.', '-'))
      ed = Date.parse(end_raw.tr('.', '-'))
      computed_days = (ed - sd).to_i # różnica dni (zgodnie z przykładem 9.09 ->17.09 daje 8)
      days_part = explicit_days ? "(#{explicit_days} dni)" : "(#{computed_days} dni)"
      # Format wyjściowy zachowuje kropki i spacje: 9.09 - 17.09.2025 (8 dni)
      start_display = start_raw.sub(/\.$/, '') # uniknij podwójnej kropki
      "#{start_display} - #{end_raw} #{days_part}".strip
    rescue
      nil
    end
  end

  def squash(str)
    str.gsub(/\s+/, ' ').strip
  end
end
