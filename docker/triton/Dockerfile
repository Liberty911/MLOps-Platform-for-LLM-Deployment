FROM nvcr.io/nvidia/tritonserver:23.10-py3

# Install additional dependencies
RUN pip install --no-cache-dir \
    transformers==4.35.0 \
    torch==2.1.0 \
    accelerate==0.24.1 \
    protobuf==3.20.3

# Copy model repository
COPY triton/models /models

# Copy custom backends
COPY triton/backends /backends

# Set environment variables
ENV MODEL_REPOSITORY=/models
ENV TRITON_SERVER_GRPC_PORT=8001
ENV TRITON_SERVER_HTTP_PORT=8000
ENV TRITON_SERVER_METRICS_PORT=8002

# Expose ports
EXPOSE 8000 8001 8002

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/v2/health/ready || exit 1

# Start Triton Server
CMD ["tritonserver", "--model-repository=/models", "--strict-model-config=false"]