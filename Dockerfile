# Build stage
FROM perl:5.36-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install cpanm
RUN curl -L https://cpanmin.us | perl - App::cpanminus

# Copy dependency files first for caching
COPY cpanfile ./

# Install Perl dependencies
RUN cpanm --notest --installdeps .

# Copy source code
COPY . .

# Run tests during build
RUN prove -l -r t/unit/

# Runtime stage
FROM perl:5.36-slim

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install cpanm for runtime deps
RUN curl -L https://cpanmin.us | perl - App::cpanminus

# Copy cpanfile and install deps
COPY cpanfile ./
RUN cpanm --notest --installdeps . && rm -rf ~/.cpanm

# Copy application from builder
COPY --from=builder /app/lib /app/lib
COPY --from=builder /app/bin /app/bin

# Add app to PATH
ENV PATH="/app/bin:${PATH}"
ENV PERL5LIB="/app/lib"

# Install cloud CLIs (optional - uncomment as needed)
# AWS CLI
# RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
#     && unzip awscliv2.zip && ./aws/install && rm -rf awscliv2.zip aws

# kubectl
# RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
#     && chmod +x kubectl && mv kubectl /usr/local/bin/

# Create non-root user
RUN useradd -m -s /bin/bash ptx
USER ptx

ENTRYPOINT ["ptx"]
CMD ["--help"]
