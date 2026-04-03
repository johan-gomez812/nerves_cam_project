defmodule CamProject.Hardware.CameraStream do
  @moduledoc """
  Streams video from Camera Module 3 via TCP using libcamera-vid.
  """
  use GenServer
  require Logger

  @port 8554
  @libcamera "/usr/bin/libcamera-vid"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_stream do
    GenServer.call(__MODULE__, :start_stream)
  end

  def stop_stream do
    GenServer.call(__MODULE__, :stop_stream)
  end

  @impl true
  def init(_) do
    {:ok, listen_socket} = :gen_tcp.listen(@port, [:binary, active: false, reuseaddr: true])
    Logger.info("CameraStream: listening on port #{@port}")
    send(self(), :accept)
    {:ok, %{listen_socket: listen_socket, client: nil, port: nil}}
  end

  @impl true
  def handle_info(:accept, state) do
    Logger.info("CameraStream: waiting for client connection")
    {:ok, client} = :gen_tcp.accept(state.listen_socket)
    Logger.info("CameraStream: client connected, starting camera")
    port = Port.open({:spawn_executable, @libcamera}, [
      :binary, :exit_status,
      args: ["-t", "0", "--width", "1280", "--height", "720",
             "--codec", "mjpeg", "--nopreview", "-o", "-"]
    ])
    {:noreply, %{state | client: client, port: port}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, client: client} = state) do
    :gen_tcp.send(client, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _}, state) do
    Logger.info("CameraStream: client disconnected")
    if state.port, do: Port.close(state.port)
    send(self(), :accept)
    {:noreply, %{state | client: nil, port: nil}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("CameraStream: camera exited with #{status}")
    {:noreply, %{state | port: nil}}
  end

  @impl true
  def handle_call(:stop_stream, _from, state) do
    if state.port, do: Port.close(state.port)
    {:reply, :ok, %{state | port: nil}}
  end
end
