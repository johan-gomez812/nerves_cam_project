defmodule CamProject.VideoCleanup do
  require Logger

  @video_dir "/data/videos"
  @max_files 10

  def cleanup do
    case File.ls(@video_dir) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(@video_dir, &1))
        |> Enum.map(fn file ->
          {:ok, stat} = File.stat(file)
          {file, stat.mtime}
        end)
        |> Enum.sort_by(fn {_file, mtime} -> mtime end)
        |> Enum.reverse()
        |> Enum.drop(@max_files)
        |> Enum.each(fn {file, _} ->
          Logger.info("Deleting old file #{file}")
          File.rm(file)
        end)

      {:error, reason} ->
        Logger.error("Cleanup failed: #{inspect(reason)}")
    end
  end
end
