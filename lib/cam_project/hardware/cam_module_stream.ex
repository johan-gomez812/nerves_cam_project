defmodule CamProject.Hardware.CameraStream do
  @moduledoc """
  Streams Camera Module 3 via HTTP MJPEG (compatible with VLC and browsers).
  Access at http://192.168.1.178:8555
  """
  use GenServer
  require Logger

  @http_port 8555
  @libcamera "/usr/bin/libcamera-vid"
  @boundary "mjpegstream"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

    def start do
    case Process.whereis(__MODULE__) do
      nil -> start_link([])
      _pid -> {:ok, :already_running}
    end
  end

  def stop do
    if Process.whereis(__MODULE__) do
      GenServer.stop(__MODULE__)
    end
  end

  @impl true
  def init(_) do
    {:ok, listen_socket} = :gen_tcp.listen(@http_port, [
      :binary, active: false, reuseaddr: true, packet: :http
    ])
    Logger.info("CameraStream: HTTP MJPEG server on port #{@http_port}")
    send(self(), :accept)
    {:ok, %{listen_socket: listen_socket}}
  end

  @impl true
  def handle_info(:accept, state) do
    {:ok, client} = :gen_tcp.accept(state.listen_socket)
    spawn(fn -> handle_client(client) end)
    send(self(), :accept)
    {:noreply, state}
  end

  defp handle_client(client) do
    # Read HTTP request
    :gen_tcp.recv(client, 0, 5000)

    # Send HTTP MJPEG headers
    headers = "HTTP/1.0 200 OK\r\n" <>
              "Content-Type: multipart/x-mixed-replace;boundary=#{@boundary}\r\n" <>
              "Cache-Control: no-cache\r\n" <>
              "\r\n"
    :gen_tcp.send(client, headers)
    :inet.setopts(client, packet: :raw)

    # Start libcamera and stream frames
    port = Port.open({:spawn_executable, @libcamera}, [
      :binary, :exit_status,
      args: ["-t", "0", "--width", "640", "--height", "480",
             "--codec", "mjpeg", "--nopreview", "-o", "-", "--flush"]
    ])

    stream_frames(client, port, <<>>)
  end

  defp stream_frames(client, port, buf) do
    receive do
      {^port, {:data, data}} ->
        new_buf = buf <> data
        {frames, remaining} = extract_frames(new_buf)
        Enum.each(frames, fn frame ->
          header = "--#{@boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: #{byte_size(frame)}\r\n\r\n"
          :gen_tcp.send(client, header <> frame <> "\r\n")
        end)
        stream_frames(client, port, remaining)
      {^port, {:exit_status, _}} ->
        :gen_tcp.close(client)
      {:tcp_closed, _} ->
        Port.close(port)
    end
  end

  defp extract_frames(data) do
    extract_frames(data, [])
  end

  defp extract_frames(data, acc) do
    case find_jpeg_frame(data) do
      {:ok, frame, rest} -> extract_frames(rest, [frame | acc])
      :incomplete -> {Enum.reverse(acc), data}
    end
  end

  defp find_jpeg_frame(<<0xFF, 0xD8, _rest::binary>> = data) do
    case :binary.match(data, <<0xFF, 0xD9>>, [{:scope, {2, byte_size(data) - 2}}]) do
      {pos, _len} ->
        frame_size = pos + 2
        <<frame::binary-size(frame_size), rest::binary>> = data
        {:ok, frame, rest}
      :nomatch ->
        :incomplete
    end
  end
  defp find_jpeg_frame(_), do: :incomplete
end
