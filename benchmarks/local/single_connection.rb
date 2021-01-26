# frozen_string_literal: true

# ruby benchmarks/local/single_connection.rb

require_relative '../../test/helpers/sockets'

class TestSingle

  include TestPuma::Sockets

  HOST = 'localhost'

  def run
    setup
    puts connect_get_response.length
  end

  def setup
    @ios_to_close = []
    @bind_type = :tcp
    @bind_port = 9292
  end

end
TestSingle.new.run
