# 1. Base Image: CUDA 12.6.3 (Stable for Ubuntu 24.04)
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04

# 2. Environment Configuration
# RESTORED: These paths are strictly required for the R linker to find CUDA libraries.
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    WHISPER_CMAKE_FLAGS="-DGGML_CUDA=1 -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=75;80;86;89;90"

# 3. Install R, r2u, BSPM, and System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg lsb-release \
    # --- Setup Keys & Repos ---
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /etc/apt/keyrings/cran.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" > /etc/apt/sources.list.d/cran.list \
    && curl -fsSL https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc | gpg --dearmor -o /etc/apt/keyrings/r2u.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/r2u.gpg] https://r2u.stat.illinois.edu/ubuntu noble main" > /etc/apt/sources.list.d/r2u.list \
    && echo "Package: *\nPin: origin r2u.stat.illinois.edu\nPin-Priority: 1000" > /etc/apt/preferences.d/99r2u \
    # --- Install Packages ---
    && apt-get update && apt-get install -y --no-install-recommends \
    r-base r-base-dev r-cran-bspm \
    python3-dbus python3-gi python3-apt \
    cmake git libcurl4-openssl-dev libssl-dev libxml2-dev libopenblas-dev ffmpeg \
    # --- Cleanup ---
    && echo "bspm::enable()" >> /etc/R/Rprofile.site \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 4. Install audio.whisper
ARG WHISPER_COMMIT=0390491
RUN git clone https://github.com/bnosac/audio.whisper.git \
    && cd audio.whisper \
    && git checkout ${WHISPER_COMMIT} \
    # Install dependencies
    && Rscript -e "install.packages('remotes'); remotes::install_deps('.', dependencies = TRUE); remotes::install_github('jmgirard/openac')" \
    # Compile with parallel jobs
    && MAKE="make -j$(nproc)" WHISPER_CMAKE_FLAGS=${WHISPER_CMAKE_FLAGS} R CMD INSTALL --no-test-load . \
    && cd .. && rm -rf audio.whisper

# 5. Verification
RUN ldd $(Rscript -e "cat(system.file('libs', 'audio.whisper.so', package='audio.whisper'))") | grep cublas