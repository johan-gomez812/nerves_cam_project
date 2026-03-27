defmodule CamProject.CameraStream do
  @moduledoc false

  require Logger

  @ffmpeg_path "/srv/erlang/lib/cam_project-0.1.0/priv/bin/ffmpeg"

  def verify_stream do
    rtsp_url = Application.get_env(:cam_project, :camera_rtsp_url)

    if is_nil(rtsp_url) do
      Logger.error("CameraStream: no camera_rtsp_url configured")
      {:error, :missing_rtsp_url}
    else
      args = [
        "-rtsp_transport", "tcp",
        "-i", rtsp_url,
        "-t", "5",
        "-f", "null",
        "-"
      ]

      Logger.info("CameraStream: starting ffmpeg verification")

      case System.cmd(@ffmpeg_path, args, stderr_to_stdout: true) do
        {output, 0} ->
          cond do
            String.contains?(output, "Video: h264") ->
              Logger.info("CameraStream: stream verification OK (video detected)")
              {:ok, output}

            true ->
              Logger.warning("CameraStream: ffmpeg finished but video signature was not detected")
              {:warning, output}
          end

        {output, status} ->
          Logger.error("CameraStream: ffmpeg failed with status #{status}")
          {:error, {status, output}}
      end
    end
  end
end
