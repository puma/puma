# this can used to test from a browser
# bundle exec bin/puma -t 4 test/rackup/chunked_encoding_csv.ru
# open localhost:9292 in browser, with Edge & Excel on Windows, the file opens

require 'csv'

BYTE_ORDER_MARK = "\377\376".force_encoding Encoding::UTF_16LE
CSV_OPTIONS = { col_sep: "\t", force_quotes: false }.freeze

run lambda { |env|
  hdrs = {}
  hdrs['Content-Type'] = 'text/csv; charset=utf-16le'
  hdrs['Content-Disposition'] = 'attachment; filename="file.csv"'

  csv_body = Enumerator.new do |yielder|
    yielder << BYTE_ORDER_MARK
    ['A,B,C,D', "1,2,3,иї_テスト"].each do |entry|
      yielder << CSV.generate_line(entry.split(','), **CSV_OPTIONS).encode(Encoding::UTF_16LE)
    end
    yielder << "\nHello World\n".encode(Encoding::UTF_16LE)
  end

  [200, hdrs, csv_body]
}
