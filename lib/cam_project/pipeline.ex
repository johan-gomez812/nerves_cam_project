defmodule CamProject.Pipeline do
  @moduledoc """
  GenServer que gestiona el ciclo de vida de la Pipeline de Membrane.
  Mantiene la API pública: start_stream, stop_stream, status.
  """
  use GenServer
  require Logger

  @hls_dir "/data/hls"
  @playlist Path.join(@hls_dir, "stream.m3u8")
  @restart_delay 3_000

  # ---------------------------------------------------------------------------
  # API Pública
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def status, do: GenServer.call(__MODULE__, :status)
  def start_stream, do: GenServer.call(__MODULE__, :start_stream)
  def stop_stream, do: GenServer.call(__MODULE__, :stop_stream)
  def restart, do: GenServer.call(__MODULE__, :restart)

  # ---------------------------------------------------------------------------
  # Callbacks del GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    File.mkdir_p!(@hls_dir)
    {:ok, %{pipeline_pid: nil, monitor_ref: nil, enabled: false, restarting: false, last_exit_reason: nil}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    running = is_pid(state.pipeline_pid) and Process.alive?(state.pipeline_pid)
    {:reply, %{running: running, restarting: state.restarting, last_exit_reason: state.last_exit_reason, playlist_exists: File.exists?(@playlist), enabled: state.enabled}, state}
  end

  @impl true
  def handle_call(:start_stream, _from, %{enabled: true} = state), do: {:reply, {:ok, :already_started}, state}

  @impl true
  def handle_call(:start_stream, _from, state) do
    cleanup_hls()
    send(self(), :launch_pipeline)
    {:reply, :ok, %{state | enabled: true, restarting: true, last_exit_reason: nil}}
  end

  @impl true
  def handle_call(:stop_stream, _from, state) do
    terminate_pipeline(state.pipeline_pid)
    cleanup_hls()
    {:reply, :ok, %{state | pipeline_pid: nil, monitor_ref: nil, enabled: false, restarting: false}}
  end

  @impl true
  def handle_call(:restart, _from, state) do
    terminate_pipeline(state.pipeline_pid)
    Process.send_after(self(), :launch_pipeline, 500)
    {:reply, :ok, %{state | pipeline_pid: nil, monitor_ref: nil, enabled: true, restarting: true}}
  end

  @impl true
  def handle_info(:launch_pipeline, %{enabled: false} = state), do: {:noreply, state}

  @impl true
  def handle_info(:launch_pipeline, state) do
    cleanup_hls()
    rtsp_url = Application.get_env(:cam_project, :camera_rtsp_url)
    Logger.info("Pipeline: Lanzando Pipeline de Membrane...")

    opts = %{rtsp_url: rtsp_url, hls_dir: @hls_dir}

    # Aquí llamamos al módulo de abajo
    case Membrane.Pipeline.start_link(CamProject.HLSPipeline, opts) do
      {:ok, _supervisor_pid, pipeline_pid} ->
        ref = Process.monitor(pipeline_pid)
        {:noreply, %{state | pipeline_pid: pipeline_pid, monitor_ref: ref, restarting: false}}

      {:error, reason} ->
        Logger.error("Pipeline: Error al arrancar: #{inspect(reason)}")
        if state.enabled, do: Process.send_after(self(), :launch_pipeline, @restart_delay)
        {:noreply, %{state | restarting: state.enabled, last_exit_reason: reason}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{pipeline_pid: pid, monitor_ref: ref, enabled: true} = state) do
    Logger.error("Pipeline: Se cayó la pipeline: #{inspect(reason)}, reiniciando...")
    Process.send_after(self(), :launch_pipeline, @restart_delay)
    {:noreply, %{state | pipeline_pid: nil, monitor_ref: nil, restarting: true, last_exit_reason: reason}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{pipeline_pid: pid, monitor_ref: ref} = state) do
    {:noreply, %{state | pipeline_pid: nil, monitor_ref: nil, restarting: false, last_exit_reason: reason}}
  end

  defp terminate_pipeline(nil), do: :ok
  defp terminate_pipeline(pid) do
    if Process.alive?(pid), do: Membrane.Pipeline.terminate(pid)
  end

  defp cleanup_hls do
    Path.join(@hls_dir, "*") |> Path.wildcard() |> Enum.each(&File.rm_rf!/1)
  end
end

# ---------------------------------------------------------------------------
# MÓDULO DE LA PIPELINE DE MEMBRANE
# ---------------------------------------------------------------------------

defmodule CamProject.HLSPipeline do
  @moduledoc false
  use Membrane.Pipeline

  # Ajustamos a 2s para que el reproductor web tenga tiempo de cargar bien
  @segment_duration Membrane.Time.seconds(2)
  @window_duration Membrane.Time.seconds(6)

  @impl true
  def handle_init(_ctx, %{rtsp_url: rtsp_url, hls_dir: hls_dir}) do
    spec =
      child(:source, %CamProject.RTSPSource{
        rtsp_url: rtsp_url
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :au,
        output_stream_structure: :avc1,
        # --- ESTA LÍNEA ES LA CLAVE PARA QUE NO SALGA NEGRO ---
        generate_best_effort_timestamps: true
      })
      |> child(:cmaf_muxer, Membrane.MP4.Muxer.CMAF)
      |> via_in(Pad.ref(:input, 0),
        options: [segment_duration: @segment_duration]
      )
      |> child(:hls_sink, %Membrane.HTTPAdaptiveStream.Sink{
        manifest_config: %Membrane.HTTPAdaptiveStream.Sink.ManifestConfig{
          module: Membrane.HTTPAdaptiveStream.HLS,
          name: "stream"
        },
        track_config: %Membrane.HTTPAdaptiveStream.Sink.TrackConfig{
          target_window_duration: @window_duration,
          mode: :live
        },
        storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{
          directory: hls_dir
        }
      })

    {[spec: spec], %{}}
  end
end
