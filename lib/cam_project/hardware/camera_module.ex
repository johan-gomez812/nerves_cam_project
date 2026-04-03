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

  def available? do
    File.exists?(@libcamera_still)
  end
end
