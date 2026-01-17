# 1. Base Image: CUDA 12.6.3 (Stable for Ubuntu 24.04)
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04

# 2. Environment Configuration
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    # Build Targets: Turing (75), Ampere (80/86), Ada (89), Hopper/Blackwell (90)
    WHISPER_CMAKE_FLAGS="-DGGML_CUDA=1 -DCMAKE_CUDA_COMPILER=nvcc -DCMAKE_CUDA_ARCHITECTURES=75;80;86;89;90"

# 3. Install R 4.5+, System Dependencies, and Build Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common dirmngr wget gpg-agent \
    && wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
    && add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" \
    && apt-get update && apt-get install -y \
    r-base r-base-dev cmake git \
    libcurl4-openssl-dev libssl-dev libxml2-dev libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 4. Install audio.whisper
RUN git clone https://github.com/bnosac/audio.whisper.git && \
    Rscript -e "install.packages('remotes'); remotes::install_deps('./audio.whisper', dependencies = TRUE)" && \
    R CMD INSTALL --no-test-load audio.whisper && \
    rm -rf audio.whisper

# 5. Verification (Fail fast if CUDA linkage is missing)
RUN ldd $(Rscript -e "cat(system.file('libs', 'audio.whisper.so', package='audio.whisper'))") | grep cublas