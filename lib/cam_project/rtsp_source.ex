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
    Logger.info("RTSPSource: connecting to #{state.rtsp_url}")

    with {:ok, session} <- RTSP.start_link(state.rtsp_url),
         {:ok, describe_resp} <- RTSP.describe(session, [{"Accept", "application/sdp"}]),
         _ = Logger.info("RTSPSource: SDP = #{inspect(describe_resp.body)}"),
         track_path = video_track_control(describe_resp),
         {:ok, _} <- RTSP.setup(session, track_path, [{"Transport", "RTP/AVP/TCP;unicast;interleaved=0-1"}]),
         {:ok, _} <- RTSP.play(session) do
      socket = RTSP.get_socket(session)
      :ok = RTSP.transfer_socket_control(session, self())
      :gen_tcp.controlling_process(socket, self())
      :inet.setopts(socket, [active: true, packet: :raw, mode: :binary])
      Process.send_after(self(), :keepalive, 30_000)
      Logger.info("RTSPSource: playing, socket=#{inspect(socket)}")
      stream_format = %H264{stream_structure: :annexb, alignment: :nalu}
      {[stream_format: {:output, stream_format}], %{state | session: session, socket: socket}}
    else
      {:error, reason} -> raise "RTSPSource: setup failed: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, _ctx, state) do
    {nalus, tcp_buf, fu_a_buf} = parse_tcp_stream(state.tcp_buf <> data, state.fu_a_buf, [])
    now = System.monotonic_time(:nanosecond)
    buffers = nalus |> Enum.with_index() |> Enum.map(fn {nalu, i} ->
      {:buffer, {:output, %Buffer{payload: @annexb_prefix <> nalu, pts: now + i * 1_000_000, dts: now + i * 1_000_000}}}
    end)
    {buffers, %{state | tcp_buf: tcp_buf, fu_a_buf: fu_a_buf}}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, _ctx, state) do
    Logger.info("RTSPSource: TCP closed")
    {[end_of_stream: :output], %{state | socket: nil}}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, _ctx, state) do
    Logger.error("RTSPSource: TCP error #{inspect(reason)}")
    {[end_of_stream: :output], %{state | socket: nil}}
  end

  @impl true
  def handle_info(:keepalive, _ctx, state) do
    Process.send_after(self(), :keepalive, 30_000)
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, %{session: session} = state) do
    if session, do: RTSP.close(session)
    {[terminate: :normal], state}
  end

  defp parse_tcp_stream(<<0x24, channel, length::16, frame::binary-size(length), rest::binary>>, fu_a_buf, acc) do
    {nalus, fu_a_buf} = if channel == 0, do: depacketize_rtp(frame, fu_a_buf), else: {[], fu_a_buf}
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

  defp video_track_control(%Response{body: %ExSDP{} = sdp}) do
    video_track = Enum.find(sdp.media, fn m -> m.type == :video end)
    control = video_track && Enum.find_value(video_track.attributes, fn
      {"control", val} -> val
      _ -> nil
    end)
    case control do
      nil -> Logger.warning("RTSPSource: no control, defaulting to trackID=0"); "trackID=0"
      val -> Logger.info("RTSPSource: track control = #{val}"); val
    end
  end
  defp video_track_control(_), do: "trackID=0"
end
