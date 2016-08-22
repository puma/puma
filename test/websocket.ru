class DoublePong
  def on_message(c, message)
    p message
    c.write(message * 2)
  end

  def call(env)
    if env['upgrade.websocket?']
      env['upgrade.websocket'] = self
      [101, {}, []]
    else
      [404, {}, ["call as a websocket"]]
    end
  end
end

run DoublePong.new
