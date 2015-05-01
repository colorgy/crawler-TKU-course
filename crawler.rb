require 'json'
require 'nokogiri'
require 'iconv'
require 'pry'

ic = Iconv.new("utf-8//translit//IGNORE","utf-8")
# ic = Iconv.new("utf-8//translit//IGNORE", "big5")
deps = JSON.parse(File.read('department.json'))

courses = []

Dir.chdir('data')
Dir.glob('*.html').each do |htm|
  str = File.read(htm)
  page = Nokogiri::HTML(str)

  _trs = page.css('tr')[2..-1]
  # dep_rows = page.css('tr').select {|d| d.text.include?("系別(Department)")}
  # binding.pry
  # dep_rows.each_with_index do |dep_row, index|
    # department_code = deps.find { |d| dep_row.text.include?(d["department"]) }["code"]

    # from = trs.index(dep_row) + 3
    # to = (dep_row != dep_rows.last) ? trs.index(dep_rows[index+1]) - 1 : trs.count-1

    # trs[from..to].each_with_index do |course_row, iindex|
    trs = _trs.select {|course_row|
      !course_row.text.include?('系別(Department)') &&
      !course_row.text.include?('選擇年級') &&
      !course_row.text.include?('教學計畫表')
    }
    trs.each_with_index do |course_row, iindex|
      # next if course_row.text.include?('系別(Department)') ||
      #         course_row.text.include?('選擇年級') ||
      #         course_row.text.include?('教學計畫表')



      department_code = File.basename(htm, '.*')
      cols = course_row.css('td')
      begin
        lecturer_code = cols[13].text.match(/\((?<code>.+)\)/)[:code] if !!cols[13].text.match(/\((?<code>.+)\)/)

        lecturer = cols[13].text.gsub(/　/, '').gsub(/\s+/, '')
        # lecturer = lecturer.scan(/(.+)\(/).first.first if lecturer.include?('(')
        lecturer.gsub!(/\(.+/, '')

        # post correction
        if lecturer == ""
          next_row = trs[iindex + 1]
          nxt_cols = next_row.css('td')
          if nxt_cols[13].text.include?(lecturer_code)
            lecturer = nxt_cols[13].text.gsub(/　/, '').gsub(/\s+/, '')
            lecturer.gsub!(/\(.+/, '')
          end
        end
      rescue Exception => e
        binding.pry
      end

      serial_num = cols[2].text.to_i.to_s.rjust(4, '0')
      if cols[2].text.to_i == 0
        next_row = trs[iindex + 1]
        nxt_cols = next_row.css('td')
        begin
          serial_num = (nxt_cols[2].text.to_i - 1).to_s.rjust(4, '0')
        rescue Exception => e
          binding.pry
        end
      end

      courses << {
        grade: cols[1].text.to_i,
        # course_code: "#{department_code}-#{cols[3].text.strip}-#{iindex}",
        course_code: "#{cols[3].text.strip}",
        code: serial_num,# use serial number as code
        required: cols[8].text.include?('必'),
        credits: cols[9].text.to_i,
        name: cols[11].text.split('　').first,
        # note: cols[10].text.split('　').last,
        lecturer: lecturer,
        department_code: department_code,
      }

    end
  # end
end

Dir.chdir("..")
File.open('courses.json', 'w') {|f| f.write(JSON.pretty_generate(courses))}
