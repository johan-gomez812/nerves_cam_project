defmodule CamProject.Snapshotter do
  @ffmpeg_path "/srv/erlang/lib/cam_project-0.1.0/priv/bin/ffmpeg"
  @snapshots_dir "/tmp/snapshots"

  def capture_snapshot do
    File.mkdir_p!(@snapshots_dir)

    timestamp =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%Y%m%d_%H%M%S")

    output_file = Path.join(@snapshots_dir, "human_#{timestamp}.jpg")
    rtsp_url = rtsp_url!()

    args = [
      "-y",
      "-rtsp_transport", "tcp",
      "-i", rtsp_url,
      "-frames:v", "1",
      "-q:v", "2",
      output_file
    ]

    port =
      Port.open({:spawn_executable, @ffmpeg_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: args
      ])

    wait_for_port(port, output_file, "")
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp wait_for_port(port, output_file, acc) do
    receive do
      {^port, {:data, data}} ->
        wait_for_port(port, output_file, acc <> data)

      {^port, {:exit_status, 0}} ->
        if File.exists?(output_file) do
          {:ok, Path.basename(output_file)}
        else
          {:error, "ffmpeg terminó bien pero no creó el snapshot"}
        end

      {^port, {:exit_status, code}} ->
        {:error, "ffmpeg failed (#{code}): #{acc}"}
    after
      15_000 ->
        Port.close(port)
        {:error, "timeout capturando snapshot"}
    end
  end

  defp rtsp_url! do
    Application.get_env(:cam_project, :camera_rtsp_url) ||
      System.get_env("CAMERA_RTSP_URL") ||
      raise "camera_rtsp_url no configurada"
  end
end
