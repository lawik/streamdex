defmodule Streamdex.Device do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, options)
  end

  def init(options) do
    device = Keyword.fetch!(options, :device)
    callback = Keyword.get(options, :callback)

    device =
      if is_nil(device.hid) do
        device.module.start(device)
      else
        device
      end

    state = %{device: device, callback: callback, reader: nil}
    state = start_reader(state)
    {:ok, state}
  end

  def handle_info({:hid_report, result}, state) do
    invoke_callback(result, state)
    {:noreply, state}
  end

  def handle_info({:hid_error, reason}, state) do
    {:stop, {:hid_error, reason}, state}
  end

  defp start_reader(state) do
    parent = self()
    device = state.device

    reader =
      spawn_link(fn -> read_loop(device, parent) end)

    %{state | reader: reader}
  end

  defp read_loop(device, parent) do
    case device.module.poll(device) do
      nil ->
        read_loop(device, parent)

      result ->
        send(parent, {:hid_report, result})
        read_loop(device, parent)
    end
  end

  defp invoke_callback(result, state) do
    case state.callback do
      callback when is_function(callback) ->
        callback.(result)

      {module, function, arguments} ->
        apply(module, function, [result | arguments])

      nil ->
        nil
    end
  end
end
