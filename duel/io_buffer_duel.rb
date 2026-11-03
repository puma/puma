# frozen_string_literal: true

require_relative "duel_helper"

# Puma::IOBuffer collects a response's head (and a small body) before
# one write to the socket. Each client keeps one, and resets it for each
# response.

duel "io_buffer: append a response head and read it out" do
  once do
    @buffer = Puma::IOBuffer.new
    @headers = rails_response_headers.to_a
  end
  @buffer << Puma::Const::HTTP_11_200
  @headers.each { |key, value| @buffer.append key, Puma::Const::COLON, value, Puma::Const::LINE_END }
  @buffer << Puma::Const::LINE_END
  @buffer.read_and_reset
end
