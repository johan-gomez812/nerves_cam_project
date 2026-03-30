defmodule CamProject.WebRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  @video_dir "/data/videos"
  @snapshots_dir "/tmp/snapshots"

  get "/" do
    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>Cam Project Dashboard</title>
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <style>
        :root { color-scheme: light dark; }
        body {
          font-family: Arial, sans-serif;
          margin: 0;
          padding: 1.25rem;
          background: #0f172a;
          color: #e5e7eb;
        }
        h1, h2, h3 { margin-top: 0; }
        a { color: #93c5fd; text-decoration: none; }
        .grid {
          display: grid;
          grid-template-columns: 2fr 1fr;
          gap: 1rem;
        }
        .card {
          background: #111827;
          border: 1px solid #1f2937;
          border-radius: 16px;
          padding: 1rem;
          box-shadow: 0 8px 24px rgba(0,0,0,0.25);
        }
        video {
          width: 100%;
          background: #000;
          border-radius: 12px;
        }
        img.snapshot {
          width: 100%;
          max-width: 520px;
          background: #000;
          border-radius: 12px;
          border: 1px solid #1f2937;
        }
        .status {
          display: inline-block;
          margin-bottom: 0.75rem;
          padding: 0.6rem 0.9rem;
          border-radius: 10px;
          font-weight: bold;
        }
        .ok { background: #064e3b; color: #d1fae5; }
        .warn { background: #78350f; color: #fef3c7; }
        .bad { background: #7f1d1d; color: #fee2e2; }
        .meta {
          color: #9ca3af;
          font-size: 0.95rem;
          margin-bottom: 1rem;
        }
        .stats {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.75rem;
          margin-top: 1rem;
        }
        .stat {
          background: #0b1220;
          border: 1px solid #1f2937;
          border-radius: 12px;
          padding: 0.9rem;
        }
        .stat-label {
          color: #9ca3af;
          font-size: 0.9rem;
          margin-bottom: 0.3rem;
        }
        .stat-value {
          font-size: 1.05rem;
          font-weight: bold;
          overflow-wrap: anywhere;
        }
        .actions {
          display: flex;
          gap: 0.75rem;
          flex-wrap: wrap;
          margin-top: 1rem;
        }
        button {
          border: 0;
          border-radius: 10px;
          padding: 0.8rem 1rem;
          font-weight: bold;
          cursor: pointer;
          background: #2563eb;
          color: white;
        }
        button.secondary {
          background: #374151;
        }
        .list {
          display: flex;
          flex-direction: column;
          gap: 0.6rem;
          max-height: 65vh;
          overflow: auto;
        }
        .item {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 0.75rem;
          background: #0b1220;
          border: 1px solid #1f2937;
          border-radius: 12px;
          padding: 0.8rem;
        }
        .item-name {
          overflow-wrap: anywhere;
        }
        .badge {
          display: inline-block;
          font-size: 0.8rem;
          color: #cbd5e1;
          background: #1e293b;
          border-radius: 999px;
          padding: 0.25rem 0.6rem;
        }
        .topbar {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 1rem;
          margin-bottom: 1rem;
        }
        .small {
          color: #9ca3af;
          font-size: 0.9rem;
        }
        @media (max-width: 900px) {
          .grid { grid-template-columns: 1fr; }
        }
      </style>
    </head>
    <body>
      <div class="topbar">
        <div>
          <h1>Cam Project Dashboard</h1>
          <div class="small">Panel de control del stream, grabaciones y detecciones</div>
        </div>
        <div>
          <a href="/health" target="_blank">/health</a>
        </div>
      </div>

      <div class="grid">
        <div class="card">
          <h2>Directo</h2>
          <div id="stream-status" class="status warn">Comprobando estado...</div>
          <div id="stream-meta" class="meta"></div>

          <video id="video" autoplay muted playsinline style="display:none;"></video>

          <div class="actions">
            <button id="start-stream-btn">Start stream</button>
            <button id="stop-stream-btn" class="secondary">Stop stream</button>
            <button id="restart-stream-btn">Restart stream</button>
            <button id="start-recording-btn">Start recording</button>
            <button id="stop-recording-btn" class="secondary">Stop recording</button>
            <button id="toggle-controls-btn" class="secondary">Mostrar/Ocultar controles</button>
          </div>

          <div class="stats">
            <div class="stat">
              <div class="stat-label">Stream running</div>
              <div id="stat-running" class="stat-value">-</div>
            </div>
            <div class="stat">
              <div class="stat-label">Playlist</div>
              <div id="stat-playlist" class="stat-value">-</div>
            </div>
            <div class="stat">
              <div class="stat-label">Grabando</div>
              <div id="stat-recording" class="stat-value">-</div>
            </div>
            <div class="stat">
              <div class="stat-label">Último archivo</div>
              <div id="stat-last-file" class="stat-value">-</div>
            </div>
          </div>

          <div class="card" style="margin-top: 1rem; background: #0b1220;">
            <h3>Grabación seleccionada</h3>
            <div id="selected-video-name" class="meta">Ninguna grabación seleccionada</div>
            <video id="recording-player" controls style="display:none;"></video>
          </div>

          <div class="card" style="margin-top: 1rem; background: #0b1220;">
            <h3>Última detección</h3>
            <div class="stats">
              <div class="stat">
                <div class="stat-label">Hora</div>
                <div id="det-last-time" class="stat-value">Sin detecciones</div>
              </div>
              <div class="stat">
                <div class="stat-label">Total</div>
                <div id="det-total" class="stat-value">0</div>
              </div>
            </div>

            <div style="margin-top: 1rem;">
              <div id="det-image-meta" class="meta">Todavía no hay snapshot</div>
              <img id="det-image" class="snapshot" src="" alt="Último snapshot" style="display:none;" />
            </div>
          </div>
        </div>

        <div class="card">
          <h2>Grabaciones</h2>
          <div class="meta">
            <span id="videos-count" class="badge">0 vídeos</span>
          </div>
          <div id="videos-list" class="list">
            <div class="small">Cargando vídeos...</div>
          </div>
        </div>
      </div>

      <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
      <script>
        const video = document.getElementById("video");
        const statusEl = document.getElementById("stream-status");
        const metaEl = document.getElementById("stream-meta");
        const videosListEl = document.getElementById("videos-list");
        const videosCountEl = document.getElementById("videos-count");

        const startStreamBtn = document.getElementById("start-stream-btn");
        const stopStreamBtn = document.getElementById("stop-stream-btn");
        const restartBtn = document.getElementById("restart-stream-btn");
        const startRecordingBtn = document.getElementById("start-recording-btn");
        const stopRecordingBtn = document.getElementById("stop-recording-btn");
        const toggleControlsBtn = document.getElementById("toggle-controls-btn");

        const statRunning = document.getElementById("stat-running");
        const statPlaylist = document.getElementById("stat-playlist");
        const statRecording = document.getElementById("stat-recording");
        const statLastFile = document.getElementById("stat-last-file");

        const recordingPlayer = document.getElementById("recording-player");
        const selectedVideoName = document.getElementById("selected-video-name");

        const detLastTime = document.getElementById("det-last-time");
        const detTotal = document.getElementById("det-total");
        const detImage = document.getElementById("det-image");
        const detImageMeta = document.getElementById("det-image-meta");

        const src = "/hls/stream.m3u8";
        let hls = null;
        let liveAttached = false;

        function setStatus(kind, text, metaText) {
          statusEl.className = "status " + kind;
          statusEl.textContent = text;
          metaEl.textContent = metaText || "";
        }

        function updateStats(stream, recorder) {
          statRunning.textContent = stream.running ? "Sí" : "No";
          statPlaylist.textContent = stream.playlist_exists ? "Existe" : "No";
          statRecording.textContent = recorder.recording ? "Sí" : "No";
          statLastFile.textContent = recorder.last_file ? recorder.last_file.split("/").pop() : "-";
        }

        function updateDetection(detection) {
          if (!detection) {
            detLastTime.textContent = "Sin detecciones";
            detTotal.textContent = "0";
            detImageMeta.textContent = "Todavía no hay snapshot";
            detImage.style.display = "none";
            detImage.removeAttribute("src");
            return;
          }

          detLastTime.textContent = detection.last_detection_at || "Sin detecciones";
          detTotal.textContent = String(detection.total_detections || 0);

          if (detection.last_snapshot_url) {
            detImageMeta.textContent = detection.last_snapshot_file || "Snapshot disponible";
            detImage.src = detection.last_snapshot_url + "?t=" + Date.now();
            detImage.style.display = "block";
          } else {
            detImageMeta.textContent = "Todavía no hay snapshot";
            detImage.style.display = "none";
            detImage.removeAttribute("src");
          }
        }

        function attachLivePlayer() {
          if (liveAttached) return;

          if (hls) {
            try { hls.destroy(); } catch (_) {}
            hls = null;
          }

          if (window.Hls && Hls.isSupported()) {
            hls = new Hls({
              liveSyncDurationCount: 1,
              liveMaxLatencyDurationCount: 3,
              maxBufferLength: 2,
              backBufferLength: 0
            });

            hls.loadSource(src);
            hls.attachMedia(video);

            hls.on(Hls.Events.MANIFEST_PARSED, function () {
              video.play().catch(() => {});
            });

            hls.on(Hls.Events.ERROR, function (_event, data) {
              if (data && data.fatal) {
                liveAttached = false;
                setStatus("warn", "🟠 Problema de reproducción", "El reproductor intentará recuperarse");
              }
            });
          } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
            video.src = src;
            video.addEventListener("loadedmetadata", function () {
              video.play().catch(() => {});
            }, { once: true });
          }

          liveAttached = true;
        }

        function detachLivePlayer() {
          liveAttached = false;

          if (hls) {
            try { hls.destroy(); } catch (_) {}
            hls = null;
          }

          video.pause();
          video.removeAttribute("src");
          video.load();
        }

        async function refreshHealth() {
          try {
            const res = await fetch("/health", { cache: "no-store" });
            const data = await res.json();
            const stream = data.stream || {};
            const recorder = data.recorder || {};
            const detection = data.detection || {};

            updateStats(stream, recorder);
            updateDetection(detection);

            if (stream.running && stream.playlist_exists && !stream.restarting) {
              video.style.display = "block";
              attachLivePlayer();
              setStatus(
                "ok",
                recorder.recording ? "🔴 Stream OK · Grabando" : "🟢 Stream OK",
                recorder.recording ? "Directo activo · Grabación en curso" : "Directo activo"
              );
            } else if (stream.restarting || stream.enabled) {
              video.style.display = "block";
              if (!liveAttached) {
                attachLivePlayer();
              }
              setStatus("warn", "🟠 Stream arrancando...", "Esperando playlist HLS");
            } else {
              detachLivePlayer();
              video.style.display = "none";
              setStatus("bad", "⚫ Stream apagado", "Pulsa Start stream para encenderlo");
            }
          } catch (_err) {
            setStatus("bad", "🔴 Error consultando estado", "No se pudo leer /health");
          }
        }

        async function refreshVideos() {
          try {
            const res = await fetch("/api/videos", { cache: "no-store" });
            const data = await res.json();
            const videos = data.videos || [];

            videosCountEl.textContent = videos.length + " vídeos";

            if (!videos.length) {
              videosListEl.innerHTML = '<div class="small">No hay grabaciones.</div>';
              return;
            }

            videosListEl.innerHTML = videos.map(function(file) {
              const encoded = encodeURIComponent(file);
              const safeName = file.replace(/'/g, "\\\\'");
              return `
                <div class="item">
                  <div class="item-name">${file}</div>
                  <div style="display:flex; gap:0.75rem; align-items:center;">
                    <a href="#" onclick="playRecording('/videos/${encoded}', '${safeName}'); return false;">Ver</a>
                    <a href="/videos/${encoded}" target="_blank">Abrir</a>
                  </div>
                </div>
              `;
            }).join("");
          } catch (_err) {
            videosListEl.innerHTML = '<div class="small">Error cargando grabaciones.</div>';
          }
        }

        async function startStream() {
          startStreamBtn.disabled = true;
          try {
            await fetch("/api/stream/start", { method: "POST" });
            setStatus("warn", "🟠 Arrancando stream...", "Esperando al directo");
            setTimeout(refreshHealth, 1000);
            setTimeout(refreshHealth, 3000);
          } finally {
            setTimeout(() => { startStreamBtn.disabled = false; }, 1500);
          }
        }

        async function stopStream() {
          stopStreamBtn.disabled = true;
          try {
            await fetch("/api/stream/stop", { method: "POST" });
            detachLivePlayer();
            video.style.display = "none";
            setStatus("bad", "⚫ Stream apagado", "Stream detenido manualmente");
            setTimeout(refreshHealth, 1000);
          } finally {
            setTimeout(() => { stopStreamBtn.disabled = false; }, 1500);
          }
        }

        async function restartStream() {
          restartBtn.disabled = true;
          liveAttached = false;
          try {
            await fetch("/api/stream/restart", { method: "POST" });
            setStatus("warn", "🟠 Reiniciando stream...", "Reinicio manual solicitado");
            setTimeout(refreshHealth, 1000);
            setTimeout(refreshHealth, 3000);
          } finally {
            setTimeout(() => {
              restartBtn.disabled = false;
            }, 3000);
          }
        }

        async function startRecording() {
          startRecordingBtn.disabled = true;
          try {
            await fetch("/api/recording/start", { method: "POST" });
            setTimeout(refreshHealth, 500);
            setTimeout(refreshHealth, 3000);
            setTimeout(refreshVideos, 12000);
          } finally {
            setTimeout(() => { startRecordingBtn.disabled = false; }, 1500);
          }
        }

        async function stopRecording() {
          stopRecordingBtn.disabled = true;
          try {
            await fetch("/api/recording/stop", { method: "POST" });
            setTimeout(refreshHealth, 500);
            setTimeout(refreshHealth, 3000);
            setTimeout(refreshVideos, 2000);
          } finally {
            setTimeout(() => { stopRecordingBtn.disabled = false; }, 1500);
          }
        }

        startStreamBtn.addEventListener("click", startStream);
        stopStreamBtn.addEventListener("click", stopStream);
        restartBtn.addEventListener("click", restartStream);
        startRecordingBtn.addEventListener("click", startRecording);
        stopRecordingBtn.addEventListener("click", stopRecording);

        toggleControlsBtn.addEventListener("click", function () {
          video.controls = !video.controls;
        });

        window.playRecording = function(url, name) {
          recordingPlayer.style.display = "block";
          recordingPlayer.src = url;
          recordingPlayer.load();
          selectedVideoName.textContent = name;
          recordingPlayer.play().catch(() => {});
        };

        refreshHealth();
        refreshVideos();
        setInterval(refreshHealth, 3000);
        setInterval(refreshVideos, 10000);
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/live" do
    conn
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  get "/health" do
    stream_status =
      try do
        CamProject.Pipeline.status()
      catch
        _, _ ->
          %{
            running: false,
            restarting: false,
            last_exit_status: nil,
            playlist_exists: false,
            enabled: false
          }
      end

    recorder_status =
      try do
        CamProject.Recorder.status()
      catch
        _, _ ->
          %{
            recording: false,
            task_pid: nil,
            segments: 0,
            last_file: nil
          }
      end

    detection_status =
      try do
        CamProject.DetectionStore.status()
      catch
        _, _ ->
          %{
            last_detection_at: nil,
            last_snapshot_file: nil,
            total_detections: 0
          }
      end

    detection =
      %{
        last_detection_at: format_detection_time(detection_status.last_detection_at),
        last_snapshot_file: detection_status.last_snapshot_file,
        last_snapshot_url:
          if detection_status.last_snapshot_file do
            "/snapshots/" <> detection_status.last_snapshot_file
          else
            nil
          end,
        total_detections: detection_status.total_detections || 0
      }

    body =
      Jason.encode!(%{
        status: "ok",
        stream: Map.update(stream_status, :last_exit_reason, nil, &inspect/1),
        recorder: Map.delete(recorder_status, :task_pid),
        detection: detection,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  get "/api/videos" do
    files =
      case File.ls(@video_dir) do
        {:ok, list} -> Enum.sort(list, :desc)
        _ -> []
      end

    body = Jason.encode!(%{videos: files})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  post "/api/stream/start" do
    result = CamProject.Pipeline.start_stream()
    body = Jason.encode!(%{ok: true, result: inspect(result)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  post "/api/stream/stop" do
    result = CamProject.Pipeline.stop_stream()
    body = Jason.encode!(%{ok: true, result: inspect(result)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  post "/api/stream/restart" do
    result = CamProject.Pipeline.restart()
    body = Jason.encode!(%{ok: true, result: inspect(result)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  post "/api/recording/start" do
    result = CamProject.Recorder.start_recording()
    body = Jason.encode!(%{ok: true, result: inspect(result)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  post "/api/recording/stop" do
    result = CamProject.Recorder.stop_recording()
    body = Jason.encode!(%{ok: true, result: inspect(result)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  match "/api/detection/human" do
    case CamProject.Snapshotter.capture_snapshot() do
      {:ok, snapshot_file} ->
        :ok = CamProject.DetectionStore.record_detection(snapshot_file)

        body =
          Jason.encode!(%{
            ok: true,
            snapshot_file: snapshot_file
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)

      {:error, reason} ->
        body =
          Jason.encode!(%{
            ok: false,
            error: to_string(reason)
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, body)
    end
  end

  get "/videos/:file" do
    path = Path.expand(Path.join(@video_dir, file))
    base = Path.expand(@video_dir)

    cond do
      not String.starts_with?(path, base) ->
        send_resp(conn, 403, "forbidden")

      not File.exists?(path) ->
        send_resp(conn, 404, "not found")

      true ->
        content_type =
          cond do
            String.ends_with?(file, ".mp4") -> "video/mp4"
            true -> "application/octet-stream"
          end

        conn
        |> put_resp_content_type(content_type)
        |> send_file(200, path)
    end
  end

  get "/snapshots/:file" do
    path = Path.expand(Path.join(@snapshots_dir, file))
    base = Path.expand(@snapshots_dir)

    cond do
      not String.starts_with?(path, base) ->
        send_resp(conn, 403, "forbidden")

      not File.exists?(path) ->
        send_resp(conn, 404, "not found")

      true ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> send_file(200, path)
    end
  end

  get "/hls/:file" do
    path = Path.expand(Path.join("/data/hls", file))
    base = Path.expand("/data/hls")

    cond do
      not String.starts_with?(path, base) ->
        send_resp(conn, 403, "forbidden")

      not File.exists?(path) ->
        send_resp(conn, 404, "not found")

      true ->
        content_type =
          cond do
            String.ends_with?(file, ".m3u8") -> "application/vnd.apple.mpegurl"
            String.ends_with?(file, ".ts") -> "video/mp2t"
            true -> "application/octet-stream"
          end

        conn
        |> put_resp_content_type(content_type)
        |> send_file(200, path)
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp format_detection_time(nil), do: nil

  defp format_detection_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_detection_time(value), do: to_string(value)
end
