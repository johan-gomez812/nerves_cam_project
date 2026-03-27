defmodule CamProject.DetectionStore do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn ->
      %{
        last_detection_at: nil,
        last_snapshot_file: nil,
        total_detections: 0
      }
    end, name: __MODULE__)
  end

  def status do
    Agent.get(__MODULE__, & &1)
  end

  def record_detection(snapshot_file) do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | last_detection_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_snapshot_file: snapshot_file,
          total_detections: state.total_detections + 1
      }
    end)

    :ok
  end
end
