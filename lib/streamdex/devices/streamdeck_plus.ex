defmodule Streamdex.Devices.StreamdeckPlus do
  alias Streamdex.Devices

  require Logger

  @image_report_length 1024
  @image_report_header_length 8
  @image_report_touchlcd_length 1024
  @image_report_touchlcd_header_length 16

  @config %{
    name: "Stream Deck +",
    keys: %{
      count: 8,
      cols: 8,
      rows: 2,
      pixel_width: 120,
      pixel_height: 120,
      image_format: :jpeg,
      flip: {false, false},
      rotation: 0
    },
    rotary_count: 4,
    image: %{
      report: %{
        length: @image_report_length,
        header_length: @image_report_header_length,
        payload_length: @image_report_length + @image_report_length,
        touchlcd_length: @image_report_touchlcd_length,
        touchlcd_header_length: @image_report_touchlcd_header_length,
        touchlcd_payload_length: @image_report_touchlcd_length + @image_report_touchlcd_length
      },
      blank_mfa: {Devices.Blanks, :plus, []}
    }
  }

  defstruct hid: nil, hid_info: nil, config: @config, module: __MODULE__

  def new(hid_device) do
    %__MODULE__{hid_info: hid_device}
  end

  def start(d) do
    {:ok, device} = open(d.hid_info)
    IO.inspect(device, label: "opened")
    d = %{d | hid: device}
    reset_key_stream(d)
    reset(d)
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

  def write(d, payload, log_as \\ nil) do
    if log_as do
      log_payload(payload, log_as)
    end

    result = HID.write(d.hid, payload)

    if log_as do
      IO.inspect(result, label: "#{log_as} result")
    end

    result
  end

  def write_feature(d, payload, log_as \\ nil) do
    if log_as do
      log_payload(payload, log_as)
    end

    result = HID.write_report(d.hid, payload)

    if log_as do
      IO.inspect(result, label: "#{log_as} result")
    end
  end

  def read_key_states(d) do
    # First byte should be report ID and can be dropped
    {:ok, binary} = read(d, 14)
    binary
  end

  def reset_key_stream(d) do
    payload = rightpad_bytes(0x02, d.config.image.report.length)

    {:ok, _} = write(d, payload, "reset key stream")
  end

  def reset(d) do
    payload = rightpad_bytes(<<0x03, 0x02>>, 32)

    {:ok, _} = write_feature(d, payload, "reset")
  end

  def set_brightness(d, percent) when is_float(percent) do
    set_brightness(d, trunc(percent * 100))
  end

  def set_brightness(d, percent) when is_integer(percent) do
    percent = min(max(percent, 0), 100)
    payload = rightpad_bytes(<<0x03, 0x08, percent>>, 32)
    write_feature(d, payload)
  end

  defp rightpad_bytes(other, to_size) when not is_binary(other) do
    rightpad_bytes(<<other>>, to_size)
  end

  defp rightpad_bytes(binary, to_size) do
    size = byte_size(binary)
    remainder = to_size - size
    binary <> <<0::size(remainder * 8)>>
  end

  defp log_payload(payload, as) do
    IO.inspect({byte_size(payload), payload}, label: "#{as} payload")
  end

  @button_down 1
  @button_up 0
  defp button_state(state) do
    case state do
      @button_down -> :down
      @button_up -> :up
    end
  end

  defp turn_state(state) do
    if state == 0 do
      {:none, 0}
    else
      {direction, base} =
        if state > 128 do
          {:left, 255}
        else
          {:right, 1}
        end

      steps = state - base + 1
      {direction, steps}
    end
  end

  defp parse_result(<<3, 5, 0, 0, r1, r2, r3, r4, _::binary>>) do
    %{
      part: :knobs,
      event: :button,
      states: [r1, r2, r3, r4] |> Enum.map(&button_state/1)
    }
  end

  defp parse_result(<<3, 5, 0, 1, r1, r2, r3, r4, _::binary>>) do
    %{
      part: :knobs,
      event: :turn,
      states: [r1, r2, r3, r4] |> Enum.map(&turn_state/1)
    }
  end

  defp parse_result(result) do
    Logger.warn("Unhandled result: #{inspect(result)}")
    nil
  end
end
