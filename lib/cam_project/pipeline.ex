defmodule CamProject.RTSPSource do
  use Membrane.Source
  import Bitwise
  require Logger

  alias Membrane.{Buffer, H264, RTSP}
  alias Membrane.RTSP.Response

  @annexb_prefix <<0, 0, 0, 1>>

  def_output_pad :output,
    flow_control: :push,
    accepted_format: %H264{stream_structure: :annexb, alignment: :nalu}

  def_options rtsp_url: [
    spec: String.t(),
    description: "RTSP stream URL (rtsp://...)"
  ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{rtsp_url: opts.rtsp_url, session: nil, socket: nil, tcp_buf: <<>>, fu_a_buf: nil}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    Logger.info("RTSPSource: Conectando a #{state.rtsp_url}")

    with {:ok, session} <- RTSP.start_link(state.rtsp_url),
         {:ok, describe_resp} <- RTSP.describe(session, [{"Accept", "application/sdp"}]),
         track_path = video_track_control(describe_resp),
         {:ok, _} <- RTSP.setup(session, track_path, [{"Transport", "RTP/AVP/TCP;unicast;interleaved=0-1"}]),
         {:ok, _} <- RTSP.play(session) do

      socket = RTSP.get_socket(session)
      :ok = RTSP.transfer_socket_control(session, self())
      :gen_tcp.controlling_process(socket, self())

      # MODO PASIVO (active: false) para que funcione el recv
      :inet.setopts(socket, [active: false, packet: :raw, mode: :binary])

      # Arrancamos el bucle de lectura
      send(self(), :poll_socket)

      Logger.info("RTSPSource: Streaming OK (Modo Polling)")

      stream_format = %H264{stream_structure: :annexb, alignment: :nalu}
      {[stream_format: {:output, stream_format}], %{state | session: session, socket: socket}}
    else
      {:error, reason} -> raise "RTSPSource: Error en setup: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_info(:poll_socket, _ctx, state) do
    case :gen_tcp.recv(state.socket, 0, 100) do
      {:ok, data} ->
        {nalus, tcp_buf, fu_a_buf} = parse_tcp_stream(state.tcp_buf <> data, state.fu_a_buf, [])

        buffers = Enum.map(nalus, fn nalu ->
          {:buffer, {:output, %Buffer{payload: @annexb_prefix <> nalu}}}
        end)

        Process.send_after(self(), :poll_socket, 5)
        {buffers, %{state | tcp_buf: tcp_buf, fu_a_buf: fu_a_buf}}

      {:error, :timeout} ->
        # No hay datos ahora, reintentamos pronto sin bloquear el pipeline
        Process.send_after(self(), :poll_socket, 10)
        {[], state}

      {:error, reason} ->
        Logger.error("RTSPSource: Error en socket: #{inspect(reason)}")
        {[end_of_stream: :output], %{state | socket: nil}}
    end
  end

  defp parse_tcp_stream(<<0x24, _channel, length::16, frame::binary-size(length), rest::binary>>, fu_a_buf, acc) do
    {nalus, fu_a_buf} = depacketize_rtp(frame, fu_a_buf)
    parse_tcp_stream(rest, fu_a_buf, acc ++ nalus)
  end
  defp parse_tcp_stream(rest, fu_a_buf, acc), do: {acc, rest, fu_a_buf}

  defp depacketize_rtp(rtp, fu_a_buf) when byte_size(rtp) < 12, do: {[], fu_a_buf}
  defp depacketize_rtp(<<_rtp_header::96, payload::binary>>, fu_a_buf) do
    case payload do
      <<nal_header, rest::binary>> -> dispatch_nal(nal_header &&& 0x1F, nal_header, rest, payload, fu_a_buf)
      _ -> {[], fu_a_buf}
    end
  end

  defp dispatch_nal(nal_type, _hdr, _rest, payload, fu_a_buf) when nal_type in 1..23, do: {[payload], fu_a_buf}
  defp dispatch_nal(24, _hdr, rest, _payload, fu_a_buf), do: {parse_stap_a(rest, []), fu_a_buf}
  defp dispatch_nal(28, nal_header, <<fu_header, fragment::binary>>, _payload, fu_a_buf) do
    start_bit = (fu_header &&& 0x80) != 0
    end_bit   = (fu_header &&& 0x40) != 0
    recon_hdr = (nal_header &&& 0x60) ||| (fu_header &&& 0x1F)
    cond do
      start_bit -> {[], {recon_hdr, [fragment]}}
      end_bit and not is_nil(fu_a_buf) ->
        {hdr, frags} = fu_a_buf
        {[IO.iodata_to_binary([<<hdr>>, Enum.reverse([fragment | frags])])], nil}
      not is_nil(fu_a_buf) ->
        {hdr, frags} = fu_a_buf
        {[], {hdr, [fragment | frags]}}
      true -> {[], nil}
    end
  end
  defp dispatch_nal(_nal_type, _hdr, _rest, _payload, fu_a_buf), do: {[], fu_a_buf}

  defp parse_stap_a(<<>>, acc), do: Enum.reverse(acc)
  defp parse_stap_a(<<size::16, nalu::binary-size(size), rest::binary>>, acc), do: parse_stap_a(rest, [nalu | acc])
  defp parse_stap_a(_, acc), do: Enum.reverse(acc)

  defp video_track_control(%Response{body: sdp}) when is_binary(sdp) do
    if String.contains?(sdp, "m=video") do
      [_, video_part] = String.split(sdp, "m=video", parts: 2)
      case Regex.run(~r/a=control:(\S+)/, video_part) do
        [_, control] -> control
        _ -> "trackID=0"
      end
    else
      "trackID=0"
    end
  end
  defp video_track_control(_), do: "trackID=0"
end

# ---------------------------------------------------------------------------
# MÓDULO DE LA PIPELINE DE MEMBRANE
# ---------------------------------------------------------------------------

defmodule CamProject.HLSPipeline do
  @moduledoc false
  use Membrane.Pipeline

  # Tiempos de segmento de 2 segundos para mayor estabilidad
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
        generate_best_effort_timestamps: true, # Clave 1: Inventa el tiempo
        sps_pps_strategy: :unsplit             # Clave 2: No bloquea si faltan headers
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
