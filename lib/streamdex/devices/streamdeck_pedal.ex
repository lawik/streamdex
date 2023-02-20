defmodule Streamdex.Devices.StreamdeckPedal do
  alias Streamdex.Devices

  import Bitwise
  require Logger

  @config %{
    name: "Stream Deck Pedal",
    keys: %{
      count: 3,
      cols: 3,
      rows: 1
    }
  }

  defstruct hid: nil, hid_info: nil, config: @config, module: __MODULE__

  def new(hid_device) do
    %__MODULE__{hid_info: hid_device}
  end

  def start(d) do
    {:ok, device} = open(d.hid_info)
    d = %{d | hid: device}
    d
  end

  def stop(d) do
    HID.close(d.hid)
  end

  def open(hid_device) do
    HID.open(hid_device.path)
  end

  def read(d, size) do
    HID.read(d.hid, size)
  end

  def poll(d) do
    case read_key_states(d) do
      "" -> nil
      <<_::8, result::binary>> -> parse_result(result)
    end
  end

  def read_feature(d, report_id, size) do
    HID.read_report(d.hid, report_id, size)
  end

  def read_key_states(d) do
    # First byte should be report ID and can be dropped
    {:ok, binary} = read(d, 14)
    binary
  end

  @button_down 1
  @button_up 0
  defp button_state(state) do
    case state do
      @button_down -> :down
      @button_up -> :up
    end
  end

  @button_count @config.keys.cols * @config.keys.rows
  defp parse_result(<<0, 3, 0, buttons::binary-size(@button_count), _::binary>>) do
    states =
      buttons
      |> :binary.bin_to_list()
      |> Enum.map(&button_state/1)

    %{
      part: :keys,
      event: :button,
      states: states
    }
  end

  defp parse_result(result) do
    Logger.warn("Unhandled result: #{inspect(result)}")
    nil
  end
end
