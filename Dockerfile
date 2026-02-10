# 1. Base Image: CUDA 12.6.3 (Stable for Ubuntu 24.04)
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04

# 2. Environment Configuration
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    # Force CMake to find nvcc and target your GPU architecture
    WHISPER_CMAKE_FLAGS="-DGGML_CUDA=1 -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=75;80;86;89;90"

# 3. Install R, r2u, BSPM, and System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg lsb-release \
    # --- Setup 1: Add CRAN Repo (Required for R 4.4+) ---
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc -o /tmp/cran_key.asc \
    && gpg --dearmor -o /etc/apt/keyrings/cran.gpg /tmp/cran_key.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" > /etc/apt/sources.list.d/cran.list \
    # --- Setup 2: Add r2u Repo (Binaries) ---
    && curl -fsSL https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc -o /tmp/r2u_key.asc \
    && gpg --dearmor -o /etc/apt/keyrings/r2u.gpg /tmp/r2u_key.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/r2u.gpg] https://r2u.stat.illinois.edu/ubuntu noble main" > /etc/apt/sources.list.d/r2u.list \
    # --- Setup 3: Pin r2u Priority ---
    && echo "Package: *" > /etc/apt/preferences.d/99r2u \
    && echo "Pin: origin r2u.stat.illinois.edu" >> /etc/apt/preferences.d/99r2u \
    && echo "Pin-Priority: 1000" >> /etc/apt/preferences.d/99r2u \
    # --- Install Packages ---
    && apt-get update && apt-get install -y --no-install-recommends \
    r-base r-base-dev \
    # CORRECTED: Install standard python libs, NOT "python3-bspm"
    python3-dbus python3-gi python3-apt \
    cmake git \
    libcurl4-openssl-dev libssl-dev libxml2-dev libopenblas-dev \
    ffmpeg \
    # --- Install bspm via apt (it is provided by r2u as r-cran-bspm) ---
    && apt-get install -y --no-install-recommends r-cran-bspm \
    # --- Cleanup ---
    && rm /tmp/cran_key.asc /tmp/r2u_key.asc \
    && rm -rf /var/lib/apt/lists/* \
    # --- Enable BSPM ---
    && echo "bspm::enable()" >> /etc/R/Rprofile.site

WORKDIR /app

# 4. Install audio.whisper
ARG WHISPER_COMMIT=0390491 

RUN nvcc --version && \
    git clone https://github.com/bnosac/audio.whisper.git && \
    # We checkout the specific commit to ensure stability and Docker caching
    cd audio.whisper && git checkout ${WHISPER_COMMIT} && cd .. && \
    # Install R dependencies
    Rscript -e "install.packages('remotes'); \
                remotes::install_deps('./audio.whisper', dependencies = TRUE); \
                remotes::install_github('jmgirard/openac')" && \
    # [Step 2: Parallel Compilation]
    # We set MAKE="make -j$(nproc)" to force the compiler to use ALL CPU cores.
    # This dramatically speeds up the compilation of the 5 different CUDA architectures.
    MAKE="make -j$(nproc)" WHISPER_CMAKE_FLAGS=${WHISPER_CMAKE_FLAGS} R CMD INSTALL --no-test-load audio.whisper && \
    rm -rf audio.whisper

# 5. Verification (Fail fast if CUDA linkage is missing)
RUN ldd $(Rscript -e "cat(system.file('libs', 'audio.whisper.so', package='audio.whisper'))") | grep cublas