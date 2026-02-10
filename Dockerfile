# ==========================================
# Stage 1: Builder (Compiles the Code)
# ==========================================
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04 AS builder

# 1. Environment Configuration
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    WHISPER_CMAKE_FLAGS="-DGGML_CUDA=1 -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=75;80;86;89;90"

# 2. Install Build Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg lsb-release \
    # --- Setup Keys & Repos ---
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /etc/apt/keyrings/cran.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" > /etc/apt/sources.list.d/cran.list \
    && curl -fsSL https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc | gpg --dearmor -o /etc/apt/keyrings/r2u.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/r2u.gpg] https://r2u.stat.illinois.edu/ubuntu noble main" > /etc/apt/sources.list.d/r2u.list \
    && echo "Package: *\nPin: origin r2u.stat.illinois.edu\nPin-Priority: 1000" > /etc/apt/preferences.d/99r2u \
    # --- Install Build Tools ---
    && apt-get update && apt-get install -y --no-install-recommends \
    r-base-dev r-cran-bspm python3-dbus python3-gi python3-apt \
    cmake git libcurl4-openssl-dev libssl-dev libxml2-dev libopenblas-dev

# 3. Build audio.whisper & openac
WORKDIR /build
ARG WHISPER_COMMIT=0390491
RUN git clone https://github.com/bnosac/audio.whisper.git \
    && cd audio.whisper \
    && git checkout ${WHISPER_COMMIT} \
    # Enable BSPM for build-time dependencies
    && echo "bspm::enable()" >> /etc/R/Rprofile.site \
    && Rscript -e "install.packages('remotes'); remotes::install_deps('.', dependencies = TRUE); remotes::install_github('jmgirard/openac')" \
    && MAKE="make -j$(nproc)" WHISPER_CMAKE_FLAGS=${WHISPER_CMAKE_FLAGS} R CMD INSTALL --no-test-load .

# ==========================================
# Stage 2: Final Runtime (Minimal Size)
# ==========================================
FROM nvidia/cuda:12.6.3-runtime-ubuntu24.04

# 1. Environment Configuration
ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# 2. Install R and Runtime Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg lsb-release \
    # --- Setup Repos (Required for R version match) ---
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /etc/apt/keyrings/cran.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" > /etc/apt/sources.list.d/cran.list \
    && curl -fsSL https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc | gpg --dearmor -o /etc/apt/keyrings/r2u.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/r2u.gpg] https://r2u.stat.illinois.edu/ubuntu noble main" > /etc/apt/sources.list.d/r2u.list \
    && echo "Package: *\nPin: origin r2u.stat.illinois.edu\nPin-Priority: 1000" > /etc/apt/preferences.d/99r2u \
    # --- Install Runtime Packages ---
    && apt-get update && apt-get install -y --no-install-recommends \
    r-base-core \
    libcurl4 libssl3 libxml2 libopenblas0 ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. Copy R Libraries (FIXED: Copying BOTH locations)
# Location 1: Dependencies installed by BSPM/apt (e.g. Rcpp, etc.)
COPY --from=builder /usr/lib/R/site-library /usr/lib/R/site-library
# Location 2: Packages installed from Source (audio.whisper, openac)
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# 4. Verification
RUN ldd $(Rscript -e "cat(system.file('libs', 'audio.whisper.so', package='audio.whisper'))") | grep cublas