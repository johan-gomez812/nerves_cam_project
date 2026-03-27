defmodule CamProject.CameraRecorder do
  @moduledoc false

  require Logger

  @ffmpeg_path "/srv/erlang/lib/cam_project-0.1.0/priv/bin/ffmpeg"
  @output_dir "/data/videos"

  def record_segment do
    rtsp_url = Application.get_env(:cam_project, :camera_rtsp_url)

    cond do
      is_nil(rtsp_url) ->
        Logger.error("CameraRecorder: no camera_rtsp_url configured")
        {:error, :missing_rtsp_url}

      true ->
        File.mkdir_p!(@output_dir)

        timestamp =
          DateTime.utc_now()
          |> Calendar.strftime("%Y%m%d_%H%M%S")

        output_file = Path.join(@output_dir, "camera_#{timestamp}.mp4")

        args = [
          "-rtsp_transport", "tcp",
          "-i", rtsp_url,
          "-t", "10",
          "-an",
          "-c:v", "copy",
          "-movflags", "+faststart",
          output_file
        ]

        Logger.info("CameraRecorder: recording segment to #{output_file}")

        case System.cmd(@ffmpeg_path, args, stderr_to_stdout: true) do
          {output, 0} ->
            Logger.info("CameraRecorder: segment recorded OK")
            {:ok, output_file, output}

          {output, status} ->
            Logger.error("CameraRecorder: ffmpeg failed with status #{status}")
            {:error, {status, output}}
        end
    end
  end
end
