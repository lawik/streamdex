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
  test "greets the world" do
    # Assumes a Streamdeck Plus is connected
    [d] = Streamdex.devices()
    assert %{hid: nil} = d
    assert %{name: "Stream Deck +"} = d.config
    d = Streamdex.start(d)
    assert %{hid: hid_ref} = d
    assert not is_nil(hid_ref)
    m = d.module

    m.set_brightness(d, 100)
    wait(d)
  end
end
