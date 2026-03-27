defmodule CamProject.ContinuousRecorder do
  use GenServer
  require Logger

  @record_every_ms 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("ContinuousRecorder: starting")
    send(self(), :record)
    {:ok, state}
  end

  @impl true
  def handle_info(:record, state) do
    case CamProject.CameraRecorder.record_segment() do
      {:ok, file, _output} ->
        Logger.info("Recorded #{file}")
        CamProject.VideoCleanup.cleanup()

      {:error, reason} ->
        Logger.error("Record failed #{inspect(reason)}")

      other ->
        Logger.warning("Unexpected result #{inspect(other)}")
    end

    Process.send_after(self(), :record, @record_every_ms)
    {:noreply, state}
  end
end
