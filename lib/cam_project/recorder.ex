defmodule CamProject.Recorder do
  use GenServer
  require Logger

  @interval_ms 10_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      recording: false,
      task_pid: nil,
      segments: 0,
      last_file: nil
    }, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def start_recording do
    GenServer.call(__MODULE__, :start_recording)
  end

  def stop_recording do
    GenServer.call(__MODULE__, :stop_recording)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:start_recording, _from, %{recording: true} = state) do
    {:reply, {:ok, :already_recording}, state}
  end

  @impl true
  def handle_call(:start_recording, _from, state) do
    Logger.info("Recorder: start recording requested")
    send(self(), :record_next_segment)
    {:reply, :ok, %{state | recording: true}}
  end

  @impl true
  def handle_call(:stop_recording, _from, %{recording: false} = state) do
    {:reply, {:ok, :already_stopped}, state}
  end

  @impl true
  def handle_call(:stop_recording, _from, state) do
    Logger.info("Recorder: stop recording requested")
    {:reply, :ok, %{state | recording: false}}
  end

  @impl true
  def handle_info(:record_next_segment, %{recording: false} = state) do
    {:noreply, %{state | task_pid: nil}}
  end

  @impl true
  def handle_info(:record_next_segment, %{task_pid: nil} = state) do
    parent = self()

    task =
      spawn(fn ->
        result = CamProject.CameraRecorder.record_segment()
        send(parent, {:segment_finished, result})
      end)

    {:noreply, %{state | task_pid: task}}
  end

  @impl true
  def handle_info(:record_next_segment, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:segment_finished, result}, state) do
    new_state =
      case result do
        {:ok, file, _output} ->
          Logger.info("Recorder: segment recorded #{file}")

          %{
            state
            | task_pid: nil,
              segments: state.segments + 1,
              last_file: file
          }

        {:error, reason} ->
          Logger.error("Recorder: segment failed #{inspect(reason)}")
          %{state | task_pid: nil}
      end

    if new_state.recording do
      Process.send_after(self(), :record_next_segment, 100)
    end

    {:noreply, new_state}
  end
end
