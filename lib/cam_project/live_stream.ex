defmodule CamProject.LiveStream do
  use GenServer
  require Logger

  @ffmpeg "/srv/erlang/lib/cam_project-0.1.0/priv/bin/ffmpeg"
  @hls_dir "/data/hls"
  @playlist Path.join(@hls_dir, "stream.m3u8")
  @restart_delay 3_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def start_stream do
    GenServer.call(__MODULE__, :start_stream)
  end

  def stop_stream do
    GenServer.call(__MODULE__, :stop_stream)
  end

  def restart do
    GenServer.call(__MODULE__, :restart)
  end

  @impl true
  def init(_state) do
    Logger.info("LiveStream: initialized in stopped state")
    File.mkdir_p!(@hls_dir)

    state = %{
      port: nil,
      restarting: false,
      last_exit_status: nil,
      enabled: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running: is_port(state.port),
       restarting: state.restarting,
       last_exit_status: state.last_exit_status,
       playlist_exists: File.exists?(@playlist),
       enabled: state.enabled
     }, state}
  end

  @impl true
  def handle_call(:start_stream, _from, %{enabled: true} = state) do
    {:reply, {:ok, :already_started}, state}
  end

  @impl true
  def handle_call(:start_stream, _from, state) do
    cleanup_hls()
    send(self(), :start_stream)

    {:reply, :ok,
     %{
       state
       | enabled: true,
         restarting: true,
         last_exit_status: nil
     }}
  end

  @impl true
  def handle_call(:stop_stream, _from, state) do
    if is_port(state.port) do
      Port.close(state.port)
    end

    cleanup_hls()

    {:reply, :ok,
     %{
       state
       | port: nil,
         enabled: false,
         restarting: false
     }}
  end

  @impl true
  def handle_call(:restart, _from, %{enabled: false} = state) do
    cleanup_hls()
    send(self(), :start_stream)

    {:reply, :ok,
     %{
       state
       | enabled: true,
         restarting: true,
         last_exit_status: nil
     }}
  end

  @impl true
  def handle_call(:restart, _from, state) do
    if is_port(state.port) do
      Port.close(state.port)
    end

    Process.send_after(self(), :start_stream, 500)

    {:reply, :ok,
     %{
       state
       | port: nil,
         enabled: true,
         restarting: true
     }}
  end

  @impl true
  def handle_info(:start_stream, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:start_stream, state) do
    cleanup_hls()

    rtsp = Application.get_env(:cam_project, :camera_rtsp_url)

    args = [
      "-rtsp_transport", "tcp",
      "-i", rtsp,
      "-fflags", "nobuffer",
      "-flags", "low_delay",
      "-an",
      "-c:v", "copy",
      "-hls_time", "1",
      "-hls_list_size", "3",
      "-hls_flags", "delete_segments",
      "-hls_segment_filename", Path.join(@hls_dir, "stream%03d.ts"),
      "-f", "hls",
      @playlist
    ]

    Logger.info("LiveStream: launching ffmpeg")

    port =
      Port.open(
        {:spawn_executable, @ffmpeg},
        [
          :binary,
          :exit_status,
          {:args, args},
          {:line, 4096},
          :stderr_to_stdout
        ]
      )

    {:noreply, %{state | port: port, restarting: false}}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    Logger.debug("LiveStream ffmpeg: #{line}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, line}}}, %{port: port} = state) do
    Logger.debug("LiveStream ffmpeg(partial): #{line}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port, enabled: true} = state) do
    Logger.error("LiveStream: ffmpeg exited with status #{status}")
    Process.send_after(self(), :start_stream, @restart_delay)

    {:noreply,
     %{
       state
       | port: nil,
         restarting: true,
         last_exit_status: status
     }}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port, enabled: false} = state) do
    Logger.info("LiveStream: ffmpeg stopped with status #{status}")

    {:noreply,
     %{
       state
       | port: nil,
         restarting: false,
         last_exit_status: status
     }}
  end

  @impl true
  def terminate(_reason, state) do
    if is_port(state.port) do
      Port.close(state.port)
    end

    :ok
  end

  defp cleanup_hls do
    Path.join(@hls_dir, "*")
    |> Path.wildcard()
    |> Enum.each(&File.rm_rf!/1)
  end
end
