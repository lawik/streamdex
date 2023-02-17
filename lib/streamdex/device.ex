defmodule Streamdex.Device do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, options)
  end

  def init(options) do
    device = Keyword.fetch!(options, :device)
    poll_rate = Keyword.get(options, :poll_rate, 100)
    callback = Keyword.get(options, :callback)

    device =
      if is_nil(device.hid) do
        device.module.start(device)
      else
        device
      end

    state = %{device: device, poll_rate: poll_rate, callback: callback}
    poll(state)
    {:ok, state}
  end

  def handle_info(:poll, state) do
    case state.device.module.poll(state.device) do
      nil -> nil
      result -> invoke_callback(result, state)
    end

    poll(state)
    {:noreply, state}
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

    {:noreply, state}
  end

  defp poll(state) do
    Process.send_after(self(), :poll, state.poll_rate)
  end
end
