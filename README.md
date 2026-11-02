# Raspberry Pi 5 Camera + ROS 2 Humble in Docker

A Docker image that makes **picamera2** work on a **Raspberry Pi 5** on top of the official
**ROS 2 Humble** ARM64 image.

> The official `arm64v8/ros:humble` image is based on Ubuntu 22.04 and ships a stock `libcamera`
> without the Raspberry Pi-specific pipelines or Python bindings. Outside of Docker, Raspberry Pi OS
> solves this with its own patched `libcamera`. Inside a container, that plumbing is missing and
> camera support breaks. This image rebuilds the missing pieces from source and wires everything up,
> so `picamera2` works in Docker on a Pi 5, together with ROS 2.

## Why this exists

Getting a Pi Camera Module running inside Docker on a Raspberry Pi 5 is surprisingly hard:

1. `picamera2` depends on the **Raspberry Pi fork of libcamera**, not the generic Ubuntu one.
2. The Pi 5 needs the **`rpi/pisp`** pipeline (Pi 0-4 use `rpi/vc4`), which is only in the RPi fork.
3. ROS 2 Humble's base image is Ubuntu 22.04, whose Python 3.10 does not look in the directories
   where meson installs Python bindings, so imports fail even after a successful build.
4. `kmsxx`/`pykms` (used for display and framebuffer work) needs the same treatment.

This image handles all four: it builds the Raspberry Pi `libcamera` fork and `kmsxx` from source,
symlinks the Python bindings into a directory Python actually searches, sets the linker/Python
environment, and verifies every import at build time so a broken image never ships.

## What's inside

| Component | Version / Pin | Notes |
|---|---|---|
| Base image | `arm64v8/ros:humble` | Ubuntu 22.04, Python 3.10, aarch64 |
| libcamera | `v0.3.1+rpt20240906` ([raspberrypi/libcamera](https://github.com/raspberrypi/libcamera)) | Built with `rpi/vc4` + `rpi/pisp` pipelines and IPAs, V4L2 adapter, GStreamer, Python bindings (`pycamera`) |
| kmsxx | commit `6cf6e88` ([tomba/kmsxx](https://github.com/tomba/kmsxx)) | Built with `pykms` |
| picamera2 | `0.3.21` | With `numpy<2` for compatibility |

## Requirements

- Raspberry Pi 5 (works on Pi 0-4 too, since the `vc4` pipeline is also built in) with a 64-bit OS
- Docker on the Pi itself, or `docker buildx` with an ARM64 builder elsewhere
  (building under QEMU emulation on x86 works but is very slow, `libcamera` compilation dominates)
- Camera module connected and enabled

## Getting started

### Build

```bash
docker build -f Dockerfile -t <your-image-name> .
```

Expect a long first build (compiling `libcamera` and `kmsxx` from source). The build ends with a
smoke test that imports `libcamera`, `pykms` and `picamera2`, so any path or linking mistake fails
the build immediately instead of haunting you at runtime.

### Run

The container needs direct access to the camera-related devices:

```bash
docker run -it --rm \
  --name pi5-cam \
  --network host \
  -v /run/udev:/run/udev:ro \
  --device /dev/dri \
  --device /dev/dma_heap \
  $(for d in /dev/video* /dev/media*; do echo --device $d; done) \
  <your-image-name>
```

- `--network host` helps with ROS 2 DDS discovery between containers and the host.
- Mounting `/run/udev` lets libcamera enumerate the media controllers.
- For a quick sanity check you can substitute all the `--device` flags with `--privileged`
  (fine for testing, not for production).

### Verify the camera

```bash
python3 -c "from picamera2 import Picamera2; print(Picamera2.global_camera_info())"
```

You should see your camera listed. If the container starts but no camera is found, see
[Troubleshooting](#troubleshooting).

## How it works

1. **Build tools**: installs `meson`, `ninja` and all native dependencies needed by `libcamera`
   and `kmsxx`.
2. **libcamera**: clones the Raspberry Pi fork at `v0.3.1+rpt20240906` and builds it with both
   `rpi/pisp` (Pi 5) and `rpi/vc4` (older Pis), plus the Python bindings (`pycamera`), V4L2
   adapter and GStreamer support.
3. **kmsxx**: pinned to a known-good commit and built with `pykms`.
4. **Python + ROS dependencies**: `picamera2`, `flask`.
5. **The Python path fix**: meson installs the bindings into
   `/usr/local/lib/aarch64-linux-gnu/python3.10/site-packages`, which is *not* on Ubuntu's default
   `sys.path`. The image symlinks the `libcamera` package and the `pykms` shared objects into
   `/usr/local/lib/python3.10/dist-packages`, and extends `LD_LIBRARY_PATH` and `PYTHONPATH`
   accordingly.
6. **Build-time verification**: `import libcamera`, `import pykms` and
   `from picamera2 import Picamera2` are all executed during the build, with diagnostics printed
   on failure.


## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `ImportError: libcamera.so not found` | `LD_LIBRARY_PATH` is wrong; the image sets it, so this usually means a custom override is in the way |
| `ModuleNotFoundError: No module named 'libcamera'` | The symlinks in `/usr/local/lib/python3.10/dist-packages` are missing; rebuild without cache |
| Container starts, but `Picamera2` finds no camera | Missing device flags (need `/dev/media*`, `/dev/video*`, `/dev/dma_heap`), or `/run/udev` not mounted; also test on the host with `rpicam-hello` |
| ROS 2 nodes don't discover each other | Try `--network host` |
| Build fails in the libcamera compile step | Check you are building for aarch64; the RPi fork and its options target ARM boards |

## Contributing

Issues and pull requests are welcome, especially reports from other Pi 5 setups (camera modules,
OS versions, Docker versions).

## License

<!-- Add your license here, e.g. MIT, Apache-2.0 -->
