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
    image =
      "priv/blank/sample.png"
      |> File.read!()
      |> m.to_key_image()

    blank = File.read!("priv/blank/plus.jpg")

    for i <- 0..7 do
      assert :ok = m.set_key_image(d, i, image)
    end

    IO.inspect(byte_size(image), label: "key image")

    # :timer.sleep(2000)
    # assert :ok = m.set_key_image(d, 1, blank)

    foo =
      "priv/blank/lcd-100x100.png"
      |> File.read!()
      |> m.to_key_image()

    assert :ok = m.set_key_image(d, 0, foo)

    bork =
      "priv/blank/lcd-800x100.png"
      |> File.read!()
      |> m.to_lcd_image(800, 100)

    File.write!("priv/blank/key-underjord.jpg", foo)
    File.write!("priv/blank/lcd-800x100.jpg", bork)

    assert :ok = m.set_lcd_image(d, 0, 0, 800, 100, bork)
    IO.inspect(byte_size(bork), label: "lcd image")
  end
end
