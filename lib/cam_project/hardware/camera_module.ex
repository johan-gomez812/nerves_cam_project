defmodule CamProject.Hardware.CameraModule do
  @moduledoc """
  Raspberry Pi Camera Module 3 (IMX708) support.
  Captures frames using libcamera via system commands.
  """

  require Logger

  @libcamera_still "/usr/bin/libcamera-still"
  @snapshot_dir "/tmp/snapshots"

  def capture_snapshot(output_path \\ nil) do
    File.mkdir_p!(@snapshot_dir)

    path = output_path || Path.join(@snapshot_dir, "cam_module_#{System.os_time(:second)}.jpg")

    case System.cmd(@libcamera_still, ["-o", path, "--immediate", "-t", "1"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("CameraModule: snapshot saved to #{path}")
        {:ok, path}
      {output, code} ->
        Logger.error("CameraModule: capture failed (#{code}): #{output}")
        {:error, output}
    end
  end

    def capture_video(duration_seconds \\ 5, output_path \\ nil) do
    File.mkdir_p!(@snapshot_dir)

    path = output_path || Path.join(@snapshot_dir, "cam_module_#{System.os_time(:second)}.h264")

    case System.cmd("/usr/bin/libcamera-vid", [
      "-o", path,
      "-t", "#{duration_seconds * 1000}",
      "--width", "1920",
      "--height", "1080"
    ], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("CameraModule: video saved to #{path}")
        {:ok, path}
      {output, code} ->
        Logger.error("CameraModule: video failed (#{code}): #{output}")
        {:error, output}
    end
  end

  def available? do
    File.exists?(@libcamera_still)
  end
end
