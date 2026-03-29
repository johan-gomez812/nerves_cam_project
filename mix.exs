defmodule CamProject.MixProject do
  use Mix.Project

  @app :cam_project
  @version "0.1.0"
  @all_targets [:bbb, :grisp2, :osd32mp1, :mangopi_mq_pro, :qemu_aarch64, :rpi, :rpi0, :rpi0_2, :rpi2, :rpi3, :rpi4, :rpi5, :x86_64]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.19",
      archives: [nerves_bootstrap: "~> 1.15"],
      listeners: listeners(Mix.target(), Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {CamProject.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.11", runtime: false},
      {:shoehorn, "~> 0.9"},
      {:ring_logger, "~> 0.10"},
      {:toolshed, "~> 0.4.0"},
      {:nerves_runtime, "~> 0.13"},
      {:nerves_pack, "~> 0.7"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      
      {:nerves_system_rpi5, "~> 0.6.4", targets: :rpi5, runtime: false},

      # Membrane pipeline (replaces LiveStream FFmpeg port)
      {:membrane_core, "~> 1.1"},
      {:membrane_rtsp_plugin, "~> 0.2"},
      {:membrane_http_adaptive_stream_plugin, "~> 0.18"},
      {:membrane_h264_plugin, "~> 0.9"},
      {:membrane_mp4_plugin, "~> 0.35"}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      
    ]
  end

  # Uncomment the following line if using Phoenix > 1.8.
  # defp listeners(:host, :dev), do: [Phoenix.CodeReloader]
  defp listeners(_, _), do: []
end
