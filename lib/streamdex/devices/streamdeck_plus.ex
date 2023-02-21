defmodule Streamdex.Devices.StreamdeckPlus do
  alias Streamdex.Devices

  import Bitwise
  require Logger

  @image_report_length 1024
  @image_report_header_length 8
  @image_report_touchlcd_length 1024
  @image_report_touchlcd_header_length 16

  @config %{
    name: "Stream Deck +",
    keys: %{
      count: 8,
      cols: 4,
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
        payload_length: @image_report_length - @image_report_header_length,
        touchlcd_length: @image_report_touchlcd_length,
        touchlcd_header_length: @image_report_touchlcd_header_length,
        touchlcd_payload_length:
          @image_report_touchlcd_length - @image_report_touchlcd_header_length
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

  def set_key_image(d, key_index, binary) do
    send_key_image_chunk(d, binary, key_index, 0)
  end

  def set_lcd_image(d, x, y, width, height, binary) do
    send_lcd_image_chunk(d, binary, x, y, width, height, 0)
  end

  def to_key_image(binary) do
    {:ok, image} = Image.from_binary(binary)

    new_binary =
      image
      |> Image.thumbnail!(@config.keys.pixel_width, fit: :fill, height: @config.keys.pixel_height)
      |> Image.write!(:memory, suffix: ".jpg", quality: 100)

    new_binary
  end

  def to_lcd_image(binary, width \\ 800, height \\ 100) do
    width = max(width, 800)
    height = max(height, 100)
    {:ok, image} = Image.from_binary(binary)

    image
    |> Image.thumbnail!(width, fit: :fill, height: height)
    |> Image.write!(:memory, suffix: ".jpg", quality: 100)
  end

  defp send_key_image_chunk(_, <<>>, _, _), do: :ok

  defp send_key_image_chunk(d, binary, key_index, page_number) do
    bytes_remaining = byte_size(binary)
    payload_length = @config.image.report.payload_length
    length = min(bytes_remaining, payload_length)

    {bytes, remainder, is_last} =
      case binary do
        <<bytes::binary-size(payload_length), remainder::binary>> ->
          {bytes, remainder, 0}

        bytes ->
          {bytes, <<>>, 1}
      end

    header = <<
      0x02,
      0x07,
      key_index &&& 0xFF,
      is_last,
      length::size(16)-unsigned-integer-little,
      page_number::size(16)-unsigned-integer-little
    >>

    8 = byte_size(header)

    payload = header <> bytes

    payload = rightpad_bytes(payload, @config.image.report.length)

    1024 = byte_size(payload)

    case write(d, payload, "set key image chunk") do
      {:ok, _} ->
        send_key_image_chunk(d, remainder, key_index, page_number + 1)

      err ->
        err
    end
  end

  defp send_lcd_image_chunk(_, <<>>, _, _, _, _, _), do: :ok

  defp send_lcd_image_chunk(d, binary, x, y, width, height, page_number) do
    if width + x > 800 do
      raise "too wide"
    end

    if height + y > 100 do
      raise "too high"
    end

    bytes_remaining = byte_size(binary)
    IO.inspect(bytes_remaining, label: "remaining")
    payload_length = @config.image.report.touchlcd_payload_length
    length = min(bytes_remaining, payload_length)

    {bytes, remainder, is_last} =
      case binary do
        <<bytes::binary-size(payload_length), remainder::binary>> ->
          {bytes, remainder, 0}

        bytes ->
          {bytes, <<>>, 1}
      end

    header =
      [
        0x02,
        0x0C,
        <<x::size(16)-unsigned-integer-little>>,
        <<y::size(16)-unsigned-integer-little>>,
        <<width::size(16)-unsigned-integer-little>>,
        <<height::size(16)-unsigned-integer-little>>,
        is_last,
        <<page_number::size(16)-unsigned-integer-little>>,
        <<length::size(16)-unsigned-integer-little>>,
        0x00
      ]
      |> IO.iodata_to_binary()

    16 = byte_size(header)

    payload = header <> bytes

    payload = rightpad_bytes(payload, @config.image.report.touchlcd_length)

    1024 = byte_size(payload)

    case write(d, payload, "set lcd image chunk") do
      {:ok, _} ->
        send_lcd_image_chunk(d, remainder, x, y, width, height, page_number + 1)

      err ->
        err
    end
  end

  defp rightpad_bytes(other, to_size) when not is_binary(other) do
    rightpad_bytes(<<other>>, to_size)
  end

  defp rightpad_bytes(binary, to_size) do
    if byte_size(binary) >= to_size do
      binary
    else
      size = byte_size(binary)
      remainder = to_size - size
      binary <> <<0::size(remainder * 8)>>
    end
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

  @button_count @config.keys.cols * @config.keys.rows
  defp parse_result(<<0, 8, 0, buttons::binary-size(@button_count), _::binary>>) do
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

  @touch_press %{
    1 => :short,
    2 => :long,
    3 => :drag
  }
  @touch_drag 3
  defp parse_result(<<2, 14, 0, type::8, _unused?::8, coords::binary-size(8), _::binary>>) do
    <<x1::8, x2::8, y1::8, y2::8, xo1::8, xo2::8, yo1::8, yo2::8>> = coords
    type = @touch_press[type]
    x = (x2 <<< 8) + x1
    y = (y2 <<< 8) + y1

    if type == :drag do
      x_out = (xo2 <<< 8) + xo1
      y_out = (yo2 <<< 8) + yo1

      %{
        part: :touchscreen,
        event: :press,
        type: type,
        start: {x, y},
        end: {x_out, y_out}
      }
    else
      %{
        part: :touchscreen,
        event: :press,
        type: type,
        point: {x, y}
      }
    end
  end

  defp parse_result(result) do
    Logger.warn("Unhandled result: #{inspect(result)}")
    nil
  end
end
