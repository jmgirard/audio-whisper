# GPU-Accelerated Whisper for R (`audio.whisper`)

A Dockerized environment for running [OpenAI's Whisper](https://github.com/openai/whisper) model directly in R with full NVIDIA GPU acceleration.

This repository provides a pre-configured Docker image that handles the complex compilation of the [`audio.whisper`](https://github.com/bnosac/audio.whisper) package and the underlying `whisper.cpp` library. It is built as a "Fat Binary," meaning it supports virtually all modern NVIDIA GPUs (RTX 20-series through RTX 50-series) out of the box without requiring local compilation.

### Why use this?
* **Reproducibility:** Everyone on the research team runs the exact same version of R (4.5.x), CUDA (12.6), and Whisper.
* **Speed:** Uses cuBLAS for GPU acceleration, making transcription significantly faster than CPU-only methods.
* **Ease of Use:** No need to install CUDA toolkits, Visual Studio, or C++ compilers on your local Windows/Linux machine.

---

## Prerequisites

1.  **Docker:** [Install Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) or Docker Engine (Linux).
2.  **NVIDIA Drivers:** Ensure your host machine has NVIDIA drivers installed (Version **555.xx** or newer is recommended).
3.  **OS-Specific Requirements:**
    * **Windows:** Ensure Docker is configured to use the **WSL2 backend**.
    * **Linux:** You **must** install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) so Docker can access your GPU.
        ```bash
        # Ubuntu/Debian example
        sudo apt-get install -y nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        ```

---

## Quick Start

### 1. Clone the Repository
```bash
git clone [https://github.com/jmgirard/audio-whisper.git](https://github.com/jmgirard/audio-whisper.git)
cd audio-whisper
```

### 2. Verify Data Folders
The repository includes two empty folders, **`models/`** and **`audio/`**. These are mounted into the container so your data persists after the container shuts down.

* **`models/`**: Whisper model weights (e.g., `ggml-base.bin`) will be saved here.
* **`audio/`**: Place your `.wav` files here to transcribe them.

### 3. Launch the Container
Use `docker compose` to build and launch an interactive R session. The first run will take a few minutes to build the image.

```bash
docker compose run --rm -it whisper
```

* `--rm`: Automatically removes the container when you exit R (saves disk space).
* `-it`: Connects your keyboard to the R console (Interactive Mode).

---

## Usage Guide

Once you are inside the R session, you can use the package immediately. The GPU is enabled by default.

### Example: Transcribing a File

```r
library(audio.whisper)

# 1. Download a model (Saved to your local 'models' folder permanently)
# Options: "tiny", "base", "small", "medium", "large-v3"
if (!file.exists("/models/ggml-base.bin")) {
  whisper_download_model("base", output_dir = "/models")
}

# 2. Load the model
# NOTE: 'use_gpu = TRUE' is critical. If successful, you will see 'BLAS = 1' in the output.
model <- whisper("/models/ggml-base.bin", use_gpu = TRUE)

# 3. Transcribe
# Ensure you have a file named 'test.wav' in your 'audio' folder
# out <- predict(model, newdata = "/data/test.wav")

# 4. Inspect Results
# print(out)
```

### Batch Processing
Since the `/data` folder inside Docker maps to your local `audio` folder, you can iterate over it:

```r
files <- list.files("/data", pattern = "\\.wav$", full.names = TRUE)
results <- lapply(files, function(f) {
  predict(model, newdata = f)
})
```

---

## Technical Details

* **Base Image:** `nvidia/cuda:12.6.3-devel-ubuntu24.04`
* **R Version:** Latest Stable (CRAN 4.0+ repository)
* **Compute Capabilities:** Compiled for architectures `75` (Turing), `80/86` (Ampere), `89` (Ada), and `90` (Hopper).
    * *Note:* Supports Blackwell (RTX 50-series) via JIT compatibility on the `90` architecture.
* **Driver Requirement:** Host machine must run NVIDIA Driver **555.xx** or higher.

---

## Troubleshooting

### "libcuda.so.1: cannot open shared object file"
**Context:** If you see this during the *build* process, it is ignored (we use `--no-test-load`).
**Context:** If you see this during *runtime* (`library(audio.whisper)`), it means the GPU was not passed through.
**Fix:** Ensure you are using `docker compose run` (which handles the `--gpus all` flag for you) and that your NVIDIA drivers are up to date.
