require 'crawler_rocks'
require 'open-uri'
require 'iconv'
require 'json'
require 'pry'
require 'capybara'
require 'capybara/poltergeist'

class TkuCourseCrawler
  include CrawlerRocks::DSL
  include Capybara::DSL

  DAYS = {
    "一" => 1,
    "二" => 2,
    "三" => 3,
    "四" => 4,
    "五" => 5,
    "六" => 6,
    "日" => 7,
  }

  def initialize year: current_year, term: current_term, update_progress: nil, after_each: nil, params: nil

    @year = params && params["year"].to_i || year
    @term = params && params["term"].to_i || term
    @update_progress_proc = update_progress
    @after_each_proc = after_each

    @query_url = "http://esquery.tku.edu.tw/acad/query.asp"
    @result_url = "http://esquery.tku.edu.tw/acad/query_result.asp"

    @download_url = "http://esquery.tku.edu.tw/acad/upload/#{@year-1911}#{@term}CLASS.EXE"
    @ic = Iconv.new("utf-8//translit//IGNORE","big5")

    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app,  js_errors: false)
    end

    Capybara.javascript_driver = :poltergeist
    Capybara.current_driver = :poltergeist
  end

  def courses
    @courses = []

    visit @query_url

    # prepare post datas
    post_datas = []
    begin
      post_datas = JSON.parse(File.read('post_datas.json'), symbolize_names: true)
    rescue; end;

    if post_datas.empty?
      deps_option_count = all('select[name="depts"] option').count
      (0..deps_option_count-1).each do |deps_option_index|
        deps_option = all('select[name="depts"] option')[deps_option_index]
        deps_option.select_option
        deps_option = nil

        sleep 1
        (0..all('select[name="dept"] option').count-1).each do |dep_option_index|
          dep_o = all('select[name="dept"] option')[dep_option_index]
          deps_option ||= all('select[name="depts"] option')[deps_option_index]
          puts dep_o.text
          begin
            post_datas << {
              deps: deps_option[:value],
              deps_name: deps_option.text,
              dep: dep_o[:value],
              dep_name: dep_o.text
            }
          rescue Exception => e; end;
        end
      end

      File.write('post_datas.json', JSON.pretty_generate(post_datas))
    end

    r = RestClient.get @query_url
    @cookies = r.cookies
    post_datas.each_with_index do |post_data, post_data_index|
      puts "#{post_data_index} / #{post_datas.count}, #{post_data[:deps_name]}-#{post_data[:dep_name]}"
      r = RestClient.post @result_url, {
        "func" => "go",
        "R1" => "1",
        "depts" => post_data[:deps],
        "sgn1" => '-',
        "dept" => post_data[:dep],
        "level" => 999
      }, cookies: @cookies
      doc = Nokogiri::HTML(@ic.iconv(r.to_s))

      dep_regex = /系別\(Department\)\：(?<dep_c>.+)\.(?<dep_n>.+)\u3000/
      course_rows = doc.css('table[bordercolorlight="#0080FF"] tr').select do |course_row|
        !course_row.text.include?('系別(Department)') &&
        !course_row.text.include?('選擇年級') &&
        !course_row.text.include?('教學計畫表') &&
        !course_row.text.strip.empty?
      end

      department = post_data[:dep_name]
      department_code = post_data[:dep]

      @year = doc.css('big').text.scan(/\d+/)[0].to_i + 1911
      @term = doc.css('big').text.scan(/\d+/)[1].to_i

      course_rows.each_with_index do |course_row, course_row_index|
        datas = course_row.css('td')
        next_course_row = course_rows[course_row_index+1]

        begin
          serial_no = datas[2] && datas[2].text.to_i.to_s.rjust(4, '0')
          if datas[1].text == "(正課)　"
            serial_no = (next_course_row.css('td')[1].text.to_i - 1).to_s.rjust(4, '0')
          end
        rescue
          binding.pry
          puts 'hello'
        end

        code = datas[3] && datas[3].text.strip.gsub(/\u3000/, '')
        code = "#{@year}-#{@term}-#{code}-#{serial_no}"

        lecturer = ""
        if datas[13].nil?
          binding.pry
        end
        datas[13] && datas[13].text.match(/(?<lec>.+)?\ \([\d|\*]+\)/) do |m|
          lecturer = m[:lec]
        end


        course_days = []
        course_periods = []
        course_locations = []
        datas[14..15].each do |time_loc_col|
          t_raws = time_loc_col.text.split('/').map{|tt| tt.strip}
          t_raws[1] && t_raws[1].split(',').each do |p|
            course_days << DAYS[t_raws[0]]
            course_periods << p.to_i
            course_locations << t_raws[2].gsub(/\u3000/, ' ').gsub(/\s+/, ' ')
          end
        end

        @courses << {
          year: @year,
          term: @term,
          code: code,
          # preserve notes for notes
          name: datas[11] && datas[11].text.gsub(/\u3000/, ' ').strip,
          lecturer: lecturer,
          department: department,
          department_code: department_code,
          required: datas[8] && datas[8].text.include?('必'),
          credits: datas[9] && datas[9].text.to_i,
          day_1: course_days[0],
          day_2: course_days[1],
          day_3: course_days[2],
          day_4: course_days[3],
          day_5: course_days[4],
          day_6: course_days[5],
          day_7: course_days[6],
          day_8: course_days[7],
          day_9: course_days[8],
          period_1: course_periods[0],
          period_2: course_periods[1],
          period_3: course_periods[2],
          period_4: course_periods[3],
          period_5: course_periods[4],
          period_6: course_periods[5],
          period_7: course_periods[6],
          period_8: course_periods[7],
          period_9: course_periods[8],
          location_1: course_locations[0],
          location_2: course_locations[1],
          location_3: course_locations[2],
          location_4: course_locations[3],
          location_5: course_locations[4],
          location_6: course_locations[5],
          location_7: course_locations[6],
          location_8: course_locations[7],
          location_9: course_locations[8],
        }
      end
    end # end each post_data

    File.write('courses.json', JSON.pretty_generate(@courses))
    @courses
  end

  def current_year
    (Time.now.month.between?(1, 7) ? Time.now.year - 1 : Time.now.year)
  end

  def current_term
    (Time.now.month.between?(2, 7) ? 2 : 1)
  end
end

cc = TkuCourseCrawler.new()
cc.courses
