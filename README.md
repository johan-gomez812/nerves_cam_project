# Nerves Cam Project

Embedded video streaming and detection system built with Nerves, Elixir, and Raspberry Pi 5, connected to a Milesight IP camera.

---

## 🚀 Overview

This project implements a complete edge-based video pipeline:

* Receives video via RTSP from an IP camera
* Processes video using FFmpeg
* Converts RTSP to HLS for web playback
* Serves a web dashboard from the Raspberry Pi
* Captures snapshots on demand or via camera events
* Handles human detection events via HTTP

👉 The entire system runs directly on the Raspberry Pi (edge computing).

---

## 🧠 Features

* 📺 Live video streaming (RTSP → HLS)
* 🌐 Web dashboard for monitoring and control
* 📸 Snapshot capture system
* 🔔 Event-based detection (camera → HTTP → backend)
* ⚙️ Stream control (start / stop / restart)

---

## 🏗️ Architecture

### Video Pipeline

```
Camera (RTSP)
   ↓
FFmpeg (Raspberry Pi)
   ↓
HLS (/data/hls)
   ↓
Web Server (Elixir)
   ↓
Browser Dashboard
```

---

### Detection Flow

```
Camera detects human
   ↓
HTTP request → /api/detection/human
   ↓
Snapshotter (FFmpeg)
   ↓
JPG image
   ↓
DetectionStore (state)
   ↓
Dashboard update
```

---

## 🧩 Tech Stack

* **Elixir / Erlang**
* **Nerves** (embedded systems)
* **Raspberry Pi 5**
* **FFmpeg**
* **Milesight IP Camera**
* **HLS (HTTP Live Streaming)**
* **RTSP**

---

## 📁 Project Structure

* `lib/cam_project/live_stream.ex` → live streaming management
* `lib/cam_project/web_router.ex` → dashboard + HTTP API
* `lib/cam_project/snapshotter.ex` → snapshot capture
* `lib/cam_project/detection_store.ex` → detection state
* `lib/cam_project/recorder.ex` → recording control

---

## ⚙️ Configuration

Example in `config/target.exs`:

```elixir
config :cam_project,
  camera_rtsp_url: "rtsp://admin:password@192.168.1.161:554/main",
  camera_http_url: "http://192.168.1.161"
```

---

## 🛠️ Build & Deploy

```bash
export MIX_TARGET=rpi5
mix deps.get
mix compile
mix firmware
mix upload <RASPBERRY_IP>
```

---

## 🌐 Dashboard

Once deployed, access the system at:

```
http://<RASPBERRY_IP>:4000/
```

---

## 📦 Requirements

* Raspberry Pi 5
* Nerves toolchain
* Network access to the IP camera
* FFmpeg (ARM64 static build)

---

## ⚠️ Notes

* FFmpeg binaries are **not included** in this repository
* You must provide your own FFmpeg binary for ARM64
* Place it according to your deployment setup

---

## 🚨 Current Status

### ✅ Working

* Live streaming (RTSP → HLS)
* Web dashboard
* Snapshot system
* Event-based detection via HTTP
* Full edge deployment on Raspberry Pi

---

### ⚠️ In Progress

* Stable MP4 recording (currently limited due to dual FFmpeg pipelines)
* Detection tuning (false positives depending on camera configuration)

---

## 🔮 Future Improvements

* Single pipeline for streaming + recording
* Smart recording based on detection events
* Automatic storage cleanup
* Snapshot persistence improvements
* Alerting / notifications system

---

## 🧠 Key Idea

This project demonstrates a complete **edge video processing system**, combining:

* hardware integration (camera + Raspberry Pi)
* real-time video processing
* web-based control interface
* event-driven architecture

---

## 📄 License

(You can add a license here if needed)
