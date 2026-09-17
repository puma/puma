# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/github_actions_summary'

class TestGithubActionsSummary < PumaTest
  def setup
    @file = Tempfile.create('puma-actions-summary')
    @file.close
  end

  def teardown
    File.unlink(@file.path) if File.exist?(@file.path)
  end

  def test_preserves_complete_entries
    summary = GithubActionsSummary.new(@file.path)
    summary.append("first\n")
    summary.append("second\n")
    assert_equal "first\nsecond\n", File.binread(@file.path)
  end

  def test_repeated_multibyte_entries_stay_under_the_limit
    summary = GithubActionsSummary.new(@file.path, max_bytes: 1024)
    100.times { summary.append("\u2714 failed\n" * 10) }
    text = File.read(@file.path, encoding: Encoding::UTF_8)
    assert_operator text.bytesize, :<=, 1024
    assert_predicate text, :valid_encoding?
    assert_equal 1, text.scan(GithubActionsSummary::LIMIT_NOTICE).length
    assert_includes text, "\u2714 failed"
  end

  def test_single_oversized_entry_is_omitted_with_notice
    summary = GithubActionsSummary.new(@file.path)
    summary.append('x' * (GithubActionsSummary::MAX_BYTES * 3))
    summary.append('later failure')
    assert_equal GithubActionsSummary::LIMIT_NOTICE, File.binread(@file.path)
  end

  def test_existing_summary_content_counts_toward_limit
    File.binwrite(@file.path, 'x' * 900)
    summary = GithubActionsSummary.new(@file.path, max_bytes: 1024)
    summary.append('y' * 200)
    assert_equal 'x' * 900 + GithubActionsSummary::LIMIT_NOTICE, File.binread(@file.path)
    assert_operator File.size(@file.path), :<=, 1024
  end

  def test_parallel_writers_respect_one_shared_budget
    summary = GithubActionsSummary.new(@file.path, max_bytes: 1024)
    threads = Array.new(4) do
      Thread.new { 100.times { summary.append("failure\n" * 5) } }
    end
    threads.each(&:join)
    assert_operator File.size(@file.path), :<=, 1024
    assert_equal 1, File.read(@file.path).scan(GithubActionsSummary::LIMIT_NOTICE).length
  end
end
