defmodule CamProject.RTSPSource do
  @moduledoc """
  Custom Membrane source element wrapping the `membrane_rtsp` library.

  Connects to an RTSP stream over TCP interleaved mode, depacketizes
  RTP/H264 per RFC 6184, and outputs Annex B NAL units on `:output`.

  Flow:
    1. `handle_playing` starts an `Membrane.RTSP` GenServer session.
    2. DESCRIBE → parse SDP for the video track control URL.
    3. SETUP with TCP interleaved transport.
    4. PLAY.
    5. Transfer socket control to this element process; enable active mode.
    6. Incoming `{:tcp, socket, data}` messages are parsed as RTSP
       interleaved frames, RTP-depacketized, and emitted as buffers.
  """

  use Membrane.Source

  require Logger

  alias Membrane.{Buffer, H264, RTSP}
  alias Membrane.RTSP.Response

  # Annex B start code prepended to every output NAL unit
  @annexb_prefix <<0, 0, 0, 1>>

  def_output_pad :output,
    flow_control: :push,
    accepted_format: %H264{stream_structure: :annexb, alignment: :nalu}

  def_options rtsp_url: [
    spec: String.t(),
    description: "RTSP stream URL (rtsp://...)"
  ]

  # ---------------------------------------------------------------------------
  # Membrane callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      rtsp_url: opts.rtsp_url,
      session: nil,
      socket: nil,
      # Accumulates incomplete interleaved frames across TCP packets
      tcp_buf: <<>>,
      # Holds in-progress FU-A reassembly: {reconstructed_nal_header, [fragment]}
      # Fragments are prepended (reversed), reversed again on completion.
      fu_a_buf: nil
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    Logger.info("RTSPSource: connecting to #{state.rtsp_url}")

    with {:ok, session} <- RTSP.start_link(state.rtsp_url),
         {:ok, describe_resp} <- RTSP.describe(session, [{"Accept", "application/sdp"}]),
         track_path = video_track_control(describe_resp),
         {:ok, _} <-
           RTSP.setup(session, track_path, [
             {"Transport", "RTP/AVP/TCP;unicast;interleaved=0-1"}
           ]),
         {:ok, _} <- RTSP.play(session) do
      socket = RTSP.get_socket(session)
      :ok = RTSP.transfer_socket_control(session, self())
      :inet.setopts(socket, active: true)

      Logger.info("RTSPSource: stream playing, socket transferred")

      stream_format = %H264{stream_structure: :annexb, alignment: :nalu}

      {[stream_format: {:output, stream_format}],
       %{state | session: session, socket: socket}}
    else
      {:error, reason} ->
        raise "RTSPSource: failed to set up RTSP stream: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_terminate_request(_ctx, %{session: session} = state) do
    if session, do: RTSP.close(session)
    {[terminate: :normal], state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, _ctx, state) do
    {nalus, tcp_buf, fu_a_buf} =
      parse_tcp_stream(state.tcp_buf <> data, state.fu_a_buf, [])

    buffers =
      Enum.map(nalus, fn nalu ->
        {:buffer, {:output, %Buffer{payload: @annexb_prefix <> nalu}}}
      end)

    {buffers, %{state | tcp_buf: tcp_buf, fu_a_buf: fu_a_buf}}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, _ctx, state) do
    Logger.warning("RTSPSource: TCP connection closed by server")
    {[end_of_stream: :output], state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, _ctx, state) do
    Logger.error("RTSPSource: TCP error: #{inspect(reason)}")
    {[end_of_stream: :output], state}
  end

  # ---------------------------------------------------------------------------
  # RTSP interleaved frame parsing
  # ---------------------------------------------------------------------------
  # Format: 0x24 | channel (1 byte) | length (2 bytes, big-endian) | payload
  # Channel 0 = RTP, channel 1 = RTCP (ignored)

  defp parse_tcp_stream(
         <<0x24, channel, length::16, frame::binary-size(length), rest::binary>>,
         fu_a_buf,
         acc
       ) do
    {nalus, fu_a_buf} =
      if channel == 0,
        do: depacketize_rtp(frame, fu_a_buf),
        else: {[], fu_a_buf}

    parse_tcp_stream(rest, fu_a_buf, acc ++ nalus)
  end

  # Incomplete frame — hold remaining bytes in tcp_buf until next packet
  defp parse_tcp_stream(rest, fu_a_buf, acc), do: {acc, rest, fu_a_buf}

  # ---------------------------------------------------------------------------
  # RTP depacketization — RFC 6184
  # ---------------------------------------------------------------------------
  # RTP fixed header is 12 bytes (skip with ::96)

  defp depacketize_rtp(rtp, fu_a_buf) when byte_size(rtp) < 12, do: {[], fu_a_buf}

  defp depacketize_rtp(<<_rtp_header::96, payload::binary>>, fu_a_buf) do
    case payload do
      <<nal_header, rest::binary>> ->
        dispatch_nal(nal_header &&& 0x1F, nal_header, rest, payload, fu_a_buf)

      _ ->
        {[], fu_a_buf}
    end
  end

  # Single NAL unit packet (types 1-23)
  defp dispatch_nal(nal_type, _hdr, _rest, payload, fu_a_buf) when nal_type in 1..23 do
    {[payload], fu_a_buf}
  end

  # STAP-A (type 24) — multiple NAL units aggregated in one RTP packet
  defp dispatch_nal(24, _hdr, rest, _payload, fu_a_buf) do
    {parse_stap_a(rest, []), fu_a_buf}
  end

  # FU-A (type 28) — single NAL unit fragmented across multiple RTP packets
  defp dispatch_nal(28, nal_header, <<fu_header, fragment::binary>>, _payload, fu_a_buf) do
    start_bit = (fu_header &&& 0x80) != 0
    end_bit   = (fu_header &&& 0x40) != 0
    # Reconstruct the original NAL header from the FU header
    recon_hdr = (nal_header &&& 0x60) ||| (fu_header &&& 0x1F)

    cond do
      start_bit ->
        # First fragment: start accumulating
        {[], {recon_hdr, [fragment]}}

      end_bit and not is_nil(fu_a_buf) ->
        # Last fragment: complete the NAL unit
        {hdr, frags} = fu_a_buf
        nalu = IO.iodata_to_binary([<<hdr>>, Enum.reverse([fragment | frags])])
        {[nalu], nil}

      not is_nil(fu_a_buf) ->
        # Middle fragment: keep accumulating
        {hdr, frags} = fu_a_buf
        {[], {hdr, [fragment | frags]}}

      true ->
        # Fragment without a preceding start (stream joined mid-NAL) — discard
        Logger.debug("RTSPSource: FU-A fragment without start, discarding")
        {[], nil}
    end
  end

  defp dispatch_nal(nal_type, _hdr, _rest, _payload, fu_a_buf) do
    Logger.debug("RTSPSource: unsupported RTP NAL type #{nal_type}, skipping")
    {[], fu_a_buf}
  end

  # STAP-A payload: 2-byte size + NAL unit, repeated
  defp parse_stap_a(<<>>, acc), do: Enum.reverse(acc)

  defp parse_stap_a(<<size::16, nalu::binary-size(size), rest::binary>>, acc),
    do: parse_stap_a(rest, [nalu | acc])

  # Guard against malformed trailing bytes
  defp parse_stap_a(_, acc), do: Enum.reverse(acc)

  # ---------------------------------------------------------------------------
  # SDP parsing — find the video media section's control attribute
  # ---------------------------------------------------------------------------

  defp video_track_control(%Response{body: sdp}) when is_binary(sdp) do
    result =
      sdp
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({false, nil}, fn
        "m=video" <> _, {_in_video, ctrl} -> {true, ctrl}
        "m=" <> _, {_in_video, ctrl}      -> {false, ctrl}
        "a=control:" <> val, {true, _}    -> {true, String.trim(val)}
        _, acc                            -> acc
      end)

    case result do
      {_, track} when is_binary(track) ->
        Logger.info("RTSPSource: video track control = #{track}")
        track

      _ ->
        Logger.warning("RTSPSource: no video track found in SDP, defaulting to trackID=0")
        "trackID=0"
    end
  end

  defp video_track_control(_), do: "trackID=0"
end
