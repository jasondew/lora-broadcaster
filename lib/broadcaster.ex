defmodule Lora.Broadcaster do
  use GenServer

  require Logger

  alias Nerves.UART

  # milliseconds
  @timeout 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[Broadcaster] Starting #{inspect(opts)}")
    pid = setup_connection(opts[:id], opts[:device])
    schedule_tick()

    {:ok, %{pid: pid}}
  end

  @impl true
  def handle_info(:tick, %{pid: pid} = state) do
    Logger.info("[Broadcaster] sending tick")

    data = to_string(DateTime.utc_now())

    case broadcast(pid, data) do
      {:ok, response} ->
        Logger.info("[Broadcaster] response: #{inspect(response)}")
        schedule_tick()

      {:error, error} ->
        Logger.error("[Broadcaster] error: #{inspect(error)}")
    end

    {:noreply, state}
  end

  ## PRIVATE FUNCTIONS

  defp broadcast(pid, data) when is_binary(data) do
    send_command(pid, "AT+SEND=0,#{String.length(data)},#{data}")
  end

  defp setup_connection(id, device) do
    {:ok, pid} = UART.start_link()

    UART.open(pid, device,
      speed: 115_200,
      active: true,
      framing: {Nerves.UART.Framing.Line, separator: "\r\n"}
    )

    send_command(pid, "AT+FACTORY")
    send_command(pid, "AT+ADDRESS=#{id}")

    pid
  end

  defp schedule_tick(), do: Process.send_after(self(), :tick, 60_000)

  defp send_command(pid, command) do
    UART.write(pid, command)

    receive do
      {:nerves_uart, _, response} ->
        {:ok, response}
    after
      @timeout ->
        {:error, :no_response}
    end
  end
end
