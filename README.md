# GPU-Accelerated Whisper for R

A Dockerized environment for running [OpenAI's Whisper](https://github.com/openai/whisper) model directly in R with full NVIDIA GPU acceleration using the [`openac`](https://github.com/jmgirard/openac) package.

This repository provides a pre-configured Docker image that handles the complex compilation of `openac`—which provides convenient wrappers for using the [bnosac/audio.whisper](https://github.com/bnosac/audio.whisper) package it builds upon (as well as for media transcoding via [ffmpeg](https://ffmpeg.org)). It is built as a "Fat Binary," meaning it supports virtually all modern NVIDIA GPUs (RTX 20-series through RTX 50-series) out of the box without requiring local compilation.

### Why use this?
* **Reproducibility:** Everyone on the research team runs the exact same version of R (4.5.x), CUDA (12.6), and Whisper.
* **Speed:** Uses cuBLAS for GPU acceleration, making transcription significantly faster than CPU-only methods.
* **Ease of Use:** No need to install CUDA toolkits, Visual Studio, or C++ compilers on your local Windows/Linux machine.


## Prerequisites

1.  **Docker:** [Install Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) or Docker Engine (Linux).
    * **Windows:** On an organization-controlled machine, you may need to get your account added to the machine's `docker-users` user group to have permission to run Docker. Contact your organization's tech support to inquire.
2.  **Git:** [Install Git](https://git-scm.com/)
3.  **NVIDIA Drivers:** Ensure your host machine has NVIDIA drivers installed (Version **555.xx** or newer is recommended).
4.  **OS-Specific Requirements:**
    * **Windows:** Ensure Docker is configured to use the **WSL2 backend**.
    * **Linux:** You **must** install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) so Docker can access your GPU.
        ```bash
        # Ubuntu/Debian example
        sudo apt-get install -y nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        ```


## Quick Start

### 1. Clone the Repository
In terminal (e.g., Powershell):

```bash
git clone https://github.com/jmgirard/audio-whisper.git
cd audio-whisper
```

### 2. Verify Data Folder
The repository includes a single folder named **`/data/`**. This folder is mounted to `/data/` inside the container, allowing files to persist after the container shuts down.

* **`/data/`**: This folder contains `harvard.wav` as a sample file.
* **Organization:** For batch processing, we recommend creating a subfolder inside `/data/` (e.g., `/data/my_audio/`) on your host machine to keep input files separate from models and output files.

### 3. Launch the Container
Use `docker compose` to build and launch an interactive R session. The first run will take a few minutes to build the image.

```bash
docker compose run --rm -it whisper
```

* `--rm`: Automatically removes the container when you exit R (saves disk space).
* `-it`: Connects your keyboard to the R console (Interactive Mode).

## Usage Guide

Once you are inside the R session, the working directory is set to `/data/`. You can use the package immediately. The GPU is enabled by default.

### Available Models
You can select different model sizes using `aw_get_model()`. Larger models generally provide higher accuracy but require more VRAM and run slower.

| Model | Size | Speed | Accuracy | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `tiny` | ~75 MB | Fastest | Lowest | Good for testing scripts |
| `base` | ~142 MB | Fast | Low | |
| `small` | ~466 MB | Moderate | Moderate | |
| `medium` | ~1.5 GB | Slow | High | Standard balance |
| `large-v3-turbo` | ~1.5 GB | Slow | Very High | **Recommended.** Same size as `medium` but performance similar to `large`. |
| `large-v3` | ~2.9 GB | Slowest | Highest | Most accurate, but highest risk of hallucination during silence. |

*Note: While larger models are more accurate, they can be more prone to "hallucinations" (inventing text, such as repeated phrases) during periods of silence.*

### Voice Activity Detection (VAD)
To reduce hallucinations and processing time, you can enable **Voice Activity Detection (VAD)**. This uses the Silero engine to detect and remove non-speech segments (silence) before transcription begins. This is highly recommended for audio with long pauses.

You can enable this by passing `whisper_args = list(vad = TRUE)` to both single-file and batch functions.

### Example: Transcribing a File

```r
# Setup
library(openac)
model <- aw_get_model("large-v3-turbo", use_gpu = TRUE)

# Transcribe sample file (included in /data)
out <- aw_transcribe("harvard.wav", model, csvfile = "harvard.csv")

# Transcribe with VAD enabled (Recommended)
out <- aw_transcribe("harvard.wav", model, csvfile = "harvard_vad.csv", whisper_args = list(vad = TRUE))
```

### Batch Processing
You can process entire folders using `aw_transcribe_dir()`. Note that you can also pass `whisper_args` here to enable VAD for the entire batch.

```r
# 1. Create a subfolder for outputs (optional, keeps things clean)
if (!dir.exists("transcripts")) dir.create("transcripts")

# 2. Batch transcribe
# Assumes you created a folder named 'my_audio' inside your local 'data' folder
# and placed your files there.
aw_transcribe_dir(
  indir = "my_audio",    # Input subfolder (relative to /data/)
  inext = "wav",         # Extension without the dot
  model = model,
  csvdir = "transcripts", # Output subfolder
  whisper_args = list(vad = TRUE) # Enable VAD for all files
)
```

## Power Users: Separate Input & Output Folders

If you have a large media library on your computer that you want to read from without mixing the output CSVs into that folder, you can mount it as a second volume.

### 1. Update `docker-compose.yml`
Add a second line to the `volumes` section. Map your local media folder to a new path inside the container, such as `/library`.

```yaml
    volumes:
      - ./data:/data                                 # Keep this for project outputs
      - C:/Users/YourName/Music/Podcasts:/library    # Access to media
```

### 2. Update your R Script
You can now read from and write to your local library.

```r
library(openac)
model <- aw_get_model("large-v3-turbo", use_gpu = TRUE)

aw_transcribe_dir(
  indir = "/library",     # Reads from C:/Users/YourName/Music/Podcasts
  inext = "mp3",
  model = model,
  wavdir = "/library/output",       # Saves converted wav files (optional)
  rdsdir = "/library/output",       # Saves compressed transcripts (optional)
  csvdir = "/library/output",       # Saves text transcripts (optional)
  whisper_args = list(vad = TRUE)   # Enable VAD
)
```

## Technical Details

* **Base Image:** `nvidia/cuda:12.6.3-devel-ubuntu24.04`
* **R Version:** Latest Stable (CRAN 4.0+ repository)
* **Compute Capabilities:** Compiled for architectures `75` (Turing), `80/86` (Ampere), `89` (Ada), and `90` (Hopper).
    * *Note:* Supports Blackwell (RTX 50-series) via JIT compatibility on the `90` architecture.
* **Driver Requirement:** Host machine must run NVIDIA Driver **555.xx** or higher.
