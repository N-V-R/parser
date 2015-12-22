# encoding: utf-8
require 'mechanize'
require 'securerandom'
require 'digest/md5'

class ShopParser
  class << self
    SITE_URL = 'http://www.a-yabloko.ru'
    IMAGES_PATH = 'images/'
    CATALOG_FILE = 'catalog.txt'
    PRODUCTS_LIMIT = 1000
    KB = 1024
    AGENT = Mechanize.new

    def parse_to_file
      current_category = ''
      products = []
      File.open(CATALOG_FILE, 'a+') do |file|
        @catalog_data = File.readlines(CATALOG_FILE)
        products = get_products.each do |product|
          product_category = product[:subcategory] || product[:category]
          if product_category != current_category
            current_category = product_category
            file.puts "Группа\t#{product[:category]}"
            file.puts "Подгруппа\t#{product[:subcategory]}" if product[:subcategory]
          end
          file.puts "Товар\t#{product[:title]}\t#{product[:subcategory] || product[:category]}\t#{product[:image]}\t#{product[:uid]}"
        end
      end
      products
    end

    def print_statistic(products)
      products.group_by { |product| product[:category] }.each do |category|
        puts "#{category[0]}\t#{category[1].length}\t#{(category[1].length.to_f / products.length * 100).round}%"
      end

      products_wo_images = products.group_by { |product| product[:image] }[nil]
      products_wo_images_count = products_wo_images ? products_wo_images.length : 0
      puts "Товаров с изображением: #{((products.length - products_wo_images_count) / products.length.to_f * 100).round}%"

      @catalog_data = File.readlines(CATALOG_FILE)
      sum = 0
      images_sizes = Dir[IMAGES_PATH+'*.jpg'].each_with_object({}) do |file, images_sizes|
        size = File.size(file)
        images_sizes[size] = File.basename(file)
        sum += size
      end
      avg_size = sum / images_sizes.keys.length / KB
      min_size = images_sizes.keys.min
      max_size = images_sizes.keys.max
      puts "Средний вес изображения: #{avg_size} Кб"
      puts "Минимальный вес изображения: #{min_size / KB} Кб (#{get_product_title_by_image(images_sizes[min_size])})"
      puts "Максимальный вес изображения: #{max_size / KB} Кб (#{get_product_title_by_image(images_sizes[max_size])})"
    end

    private

    def get_products
      products = []
      get_categories.each do |category|
        break if products_limit?(products)

        if category[:subcategories].empty?
          get_products_from_category(category, products)
        else
          category[:subcategories].each { |subcategory| get_products_from_category(category, products, subcategory) }
        end
      end
      products
    end

    def get_categories
      page = AGENT.get(SITE_URL).parser
      page_menu = page.css('#catalog-menu')[1].css(' > ul > li')
      page_menu.inject([]) do |categories, li|
        a = li.at(' > a')
        li_a = li.css(' > ul > li > a')

        subcategories = li_a.inject([]) { |subcategories, a| subcategories << {title: a.text, path: a[:href]} }
        categories << {title: a.text, path: a[:href], subcategories: subcategories}
      end
    end

    def get_pages_count(page)
      last_page = page.at('.page a.end')
      last_page ? last_page[:href][/page\/(\d+)/, 1].to_i : 1
    end

    def get_products_from_category(category, products, subcategory = nil)
      current_category = subcategory || category
      page = AGENT.get(SITE_URL + current_category[:path]).parser
      get_pages_count(page).times do |i|
        break if products_limit?(products)

        page = AGENT.get(SITE_URL + current_category[:path] + 'page/' + (i+1).to_s).parser unless i == 0
        get_products_from_page(page, products, category, subcategory)
      end
    end

    def get_products_from_page(page, products, category, subcategory = nil)
      page_items = page.css('.goods > .item')
      page_items.each do |item|
        break if products_limit?(products)

        title = item.at('a.name').text
        image_path = item.at('a.img')[:style][/background-image:url\('(.+)'\)/, 1]
        uid = Digest::MD5.hexdigest(title + image_path)
        next if product_parsed?(uid)

        image_name = download_image(SITE_URL + image_path)
        products << {
            title: title,
            category: category[:title],
            subcategory: subcategory ? subcategory[:title] : nil,
            image: image_name,
            uid: uid
        }
      end
    end

    def get_product_title_by_image(image_name)
      @catalog_data.each { |line| return line[/\t(.+?)\t/, 1] if line.include?(image_name) }
      ''
    end

    def download_image(url)
      return if url.include?('no_img')

      image_name = SecureRandom.hex + '.jpg'
      AGENT.get(url).save(IMAGES_PATH + image_name)
      image_name
    end

    def products_limit?(products)
      products.length >= PRODUCTS_LIMIT
    end

    def product_parsed?(uid)
      @catalog_data.any? { |line| line.include?(uid) }
    end
  end
end

ShopParser.print_statistic(ShopParser.parse_to_file)
