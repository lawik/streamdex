defmodule StreamdexTest do
  use ExUnit.Case
  doctest Streamdex

  def wait(d) do
    :timer.sleep(100)

    d.module.read_key_states(d)
    |> case do
      "" -> nil
      binary -> IO.inspect(binary)
    end

    wait(d)
  end

  @tag timeout: :infinity
  test "foo" do
    # Assumes a Streamdeck Plus is connected
    [d] = Streamdex.devices()
    assert %{hid: nil} = d
    assert %{name: "Stream Deck +"} = d.config
    d = Streamdex.start(d)
    assert %{hid: hid_ref} = d
    assert not is_nil(hid_ref)
    m = d.module

    m.set_brightness(d, 100)
    # wait(d)
    # image =
    #   "priv/blank/sample.png"
    #   |> File.read!()
    #   |> m.to_key_image()

    # blank = File.read!("priv/blank/plus.jpg")
    # assert :ok = m.set_key_image(d, 1, image)
    # :timer.sleep(2000)
    # assert :ok = m.set_key_image(d, 1, blank)

    image =
      "priv/blank/lcd-800x100.png"
      |> File.read!()
      |> m.to_lcd_image()

    assert :ok = m.set_lcd_image(d, 0, 0, 800, 100, image)

    :timer.sleep(2000)
  end
end
