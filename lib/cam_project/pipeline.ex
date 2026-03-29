defmodule CamProject.Pipeline do
  @moduledoc """
  Membrane-based HLS live stream pipeline.

  Replaces `CamProject.LiveStream` (FFmpeg port) with native Membrane elements:
    - `Membrane.RTSP.Source`  — ingests the RTSP stream over TCP
    - `Membrane.H264.Parser`  — normalises NAL units into access-unit alignment
    - `Membrane.HTTPAdaptiveStream.Sink` — writes HLS segments + m3u8 manifest

  Public API is identical to LiveStream: `start_stream/0`, `stop_stream/0`,
  `status/0`.  The GenServer wrapper manages lifecycle and auto-restarts the
  Membrane pipeline on crash, mirroring the Port-based restart logic.
  """

  use GenServer
  require Logger

  @hls_dir "/data/hls"
  @playlist Path.join(@hls_dir, "stream.m3u8")
  @restart_delay 3_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    File.mkdir_p!(@hls_dir)

    {:ok,
     %{
       pipeline_pid: nil,
       monitor_ref: nil,
       enabled: false,
       restarting: false,
       last_exit_reason: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    running =
      is_pid(state.pipeline_pid) and Process.alive?(state.pipeline_pid)

    {:reply,
     %{
       running: running,
       restarting: state.restarting,
       last_exit_reason: state.last_exit_reason,
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
    send(self(), :launch_pipeline)

    {:reply, :ok,
     %{state | enabled: true, restarting: true, last_exit_reason: nil}}
  end

  @impl true
  def handle_call(:stop_stream, _from, state) do
    terminate_pipeline(state.pipeline_pid)
    cleanup_hls()

    {:reply, :ok,
     %{state | pipeline_pid: nil, monitor_ref: nil, enabled: false, restarting: false}}
  end

  # Restart when pipeline is not running: same as start_stream
  @impl true
  def handle_call(:restart, _from, %{enabled: false} = state) do
    cleanup_hls()
    send(self(), :launch_pipeline)

    {:reply, :ok,
     %{state | enabled: true, restarting: true, last_exit_reason: nil}}
  end

  # Restart when pipeline is running: terminate and relaunch after 500 ms
  @impl true
  def handle_call(:restart, _from, state) do
    terminate_pipeline(state.pipeline_pid)
    Process.send_after(self(), :launch_pipeline, 500)

    {:reply, :ok,
     %{state | pipeline_pid: nil, monitor_ref: nil, enabled: true, restarting: true}}
  end

  @impl true
  def handle_info(:launch_pipeline, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:launch_pipeline, state) do
    cleanup_hls()
    rtsp_url = Application.get_env(:cam_project, :camera_rtsp_url)

    Logger.info("Pipeline: launching Membrane HLS pipeline")

    opts = %{rtsp_url: rtsp_url, hls_dir: @hls_dir}

    case Membrane.Pipeline.start_link(CamProject.HLSPipeline, opts) do
      {:ok, _supervisor_pid, pipeline_pid} ->
        ref = Process.monitor(pipeline_pid)
        {:noreply, %{state | pipeline_pid: pipeline_pid, monitor_ref: ref, restarting: false}}

      {:error, reason} ->
        Logger.error("Pipeline: failed to start: #{inspect(reason)}")

        if state.enabled do
          Process.send_after(self(), :launch_pipeline, @restart_delay)
        end

        {:noreply, %{state | restarting: state.enabled, last_exit_reason: reason}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{pipeline_pid: pid, monitor_ref: ref, enabled: true} = state
      ) do
    Logger.error("Pipeline: Membrane pipeline exited: #{inspect(reason)}, restarting in #{@restart_delay}ms")
    Process.send_after(self(), :launch_pipeline, @restart_delay)

    {:noreply,
     %{state | pipeline_pid: nil, monitor_ref: nil, restarting: true, last_exit_reason: reason}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{pipeline_pid: pid, monitor_ref: ref} = state
      ) do
    Logger.info("Pipeline: Membrane pipeline stopped: #{inspect(reason)}")

    {:noreply,
     %{state | pipeline_pid: nil, monitor_ref: nil, restarting: false, last_exit_reason: reason}}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp terminate_pipeline(nil), do: :ok

  defp terminate_pipeline(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Membrane.Pipeline.terminate(pid)
    end
  end

  defp cleanup_hls do
    Path.join(@hls_dir, "*")
    |> Path.wildcard()
    |> Enum.each(&File.rm_rf!/1)
  end
end

defmodule CamProject.HLSPipeline do
  @moduledoc false

  use Membrane.Pipeline

  # Segment duration matches the original FFmpeg -hls_time 1 setting.
  # Window of 3 segments matches -hls_list_size 3.
  @segment_duration Membrane.Time.seconds(1)
  @window_duration Membrane.Time.seconds(3)

  @impl true
  def handle_init(_ctx, %{rtsp_url: rtsp_url, hls_dir: hls_dir}) do
    spec =
      child(:source, %Membrane.RTSP.Source{
        stream_uri: rtsp_url,
        transport: :tcp,
        allowed_media_types: [:video]
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        # Access-unit alignment is required by the CMAF muxer
        output_alignment: :au
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
