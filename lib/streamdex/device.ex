defmodule Streamdex.Device do
  use GenServer

  @default_keep_alive_interval :timer.seconds(30)

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, options)
  end

  def init(options) do
    device = Keyword.fetch!(options, :device)
    callback = Keyword.get(options, :callback)
    keep_alive_interval = Keyword.get(options, :keep_alive_interval, @default_keep_alive_interval)

    device =
      if is_nil(device.hid) do
        device.module.start(device)
      else
        device
      end

    state = %{
      device: device,
      callback: callback,
      reader: nil,
      keep_alive_interval: keep_alive_interval
    }

    state = start_reader(state)
    schedule_keep_alive(state)
    {:ok, state}
  end

  def handle_info({:hid_report, result}, state) do
    invoke_callback(result, state)
    {:noreply, state}
  end

  def handle_info({:hid_error, reason}, state) do
    {:stop, {:hid_error, reason}, state}
  end

  def handle_info(:keep_alive, state) do
    state.device.module.keep_alive(state.device)
    schedule_keep_alive(state)
    {:noreply, state}
  end

  defp schedule_keep_alive(%{keep_alive_interval: interval}) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :keep_alive, interval)
  end

  defp schedule_keep_alive(_), do: :ok

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
