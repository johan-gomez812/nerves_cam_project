defmodule CamProject.CameraProbe do
  @moduledoc false

  require Logger

  def check do
    rtsp_url = Application.get_env(:cam_project, :camera_rtsp_url)

    case parse_rtsp_host_port_path(rtsp_url) do
      {:ok, host, port, path} ->
        Logger.info("CameraProbe: checking RTSP #{tuple_host_to_string(host)}:#{port}#{path}")

        with {:ok, socket} <- :gen_tcp.connect(host, port, [:binary, active: false], 3_000),
             :ok <- :gen_tcp.send(socket, options_request(host, port, path)),
             {:ok, response} <- :gen_tcp.recv(socket, 0, 3_000) do
          :gen_tcp.close(socket)

          if String.contains?(response, "RTSP/1.0 200 OK") do
            Logger.info("CameraProbe: camera RTSP reachable and responding OK")
            {:ok, response}
          else
            Logger.error("CameraProbe: unexpected RTSP response: #{inspect(response)}")
            {:error, {:unexpected_response, response}}
          end
        else
          {:error, reason} = error ->
            Logger.error("CameraProbe: RTSP check failed: #{inspect(reason)}")
            error
        end

      {:error, reason} = error ->
        Logger.error("CameraProbe: invalid RTSP URL: #{inspect(reason)}")
        error
    end
  end

  defp parse_rtsp_host_port_path(nil), do: {:error, :missing_url}

  defp parse_rtsp_host_port_path(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != "rtsp" ->
        {:error, :invalid_scheme}

      is_nil(uri.host) ->
        {:error, :missing_host}

      true ->
        host =
          uri.host
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
          |> List.to_tuple()

        port = uri.port || 554
        path = uri.path || "/"

        {:ok, host, port, path}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  defp options_request(host, port, path) do
    "OPTIONS rtsp://#{tuple_host_to_string(host)}:#{port}#{path} RTSP/1.0\r\n" <>
      "CSeq: 1\r\n" <>
      "\r\n"
  end

  defp tuple_host_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end
