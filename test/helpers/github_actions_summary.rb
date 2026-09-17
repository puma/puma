# frozen_string_literal: true

# Keep complete retry entries below GitHub's 1 MiB per-step summary limit.
# The normal test log retains all details even when the summary is full.
class GithubActionsSummary
  MAX_BYTES = 1_000_000
  LIMIT_NOTICE = "\nFurther retry details omitted to keep this summary below GitHub's size limit. See the full test log.\n"

  def initialize(path, max_bytes: MAX_BYTES)
    @path = path
    @max_bytes = max_bytes
    @mutex = Mutex.new
    @truncated = false
  end

  def append(text)
    @mutex.synchronize do
      return if @truncated

      # Binary mode prevents Windows newline conversion changing the byte count.
      File.open(@path, 'ab') do |file|
        if file.size + text.bytesize + LIMIT_NOTICE.bytesize <= @max_bytes
          file.write(text)
        else
          file.write(LIMIT_NOTICE) if file.size + LIMIT_NOTICE.bytesize <= @max_bytes
          @truncated = true
        end
      end
    end
  end
end
