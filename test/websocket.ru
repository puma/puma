class DoublePong
  def on_message(message)
    p message
    write(message * 2)
  end

  def call(env)
    if env['upgrade.websocket?']
      env['upgrade.websocket'].call self
      [101, {}, []]
    else
      [404, {}, ["call as a websocket"]]
    end
  end
end

run DoublePong.new
