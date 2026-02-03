# MLOps Platform for LLM Deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A production-grade MLOps platform for deploying, serving, and managing Large Language Models (LLMs) on Kubernetes with NVIDIA Triton Inference Server, KServe, Ray, and Weights & Biases.

## Features

- **Multi-Framework Support**: Deploy models from Hugging Face, PyTorch, TensorFlow, ONNX
- **High-Performance Inference**: NVIDIA Triton with GPU acceleration
- **Serverless Inference**: KServe/Knative for auto-scaling and pay-per-use
- **Distributed Training**: Ray for distributed fine-tuning and batch inference
- **Experiment Tracking**: Weights & Biases integration for model versioning
- **Production Ready**: TLS/SSL, monitoring, logging, and auto-scaling
- **Multi-Model Serving**: Serve multiple LLMs simultaneously with isolation
- **Cost Optimization**: Spot instances, GPU sharing, and auto-scaling

## Project Structure

terraform/     # Infrastructure as Code
kubernetes/    # K8s manifests
kserve/        # Serverless inference
triton/        # NVIDIA Triton configs
ray/           # Distributed computing
wandb/         # Experiment tracking
scripts/       # Deployment scripts
examples/      # Usage examples

## Tech Stack
- Orchestration: Kubernetes (EKS)
- Model Serving: NVIDIA Triton, KServe
- Networking: Nginx Ingress, Cert-Manager
- Serverless: Knative
- Distributed Computing: Ray
- Experiment Tracking: Weights & Biases
- Monitoring: Prometheus, Grafana
- CI/CD: GitHub Actions, Argo CD
- Storage: AWS S3, EFS


## Supported Models
- LLaMA 2 (7B, 13B, 70B)
- Falcon (7B, 40B)
- Mistral (7B)
- CodeLlama
- Custom HuggingFace models

## Architecture

![Architecture Diagram](docs/images/architecture.png)

## Quick Start

### Prerequisites
- AWS Account with proper IAM permissions
- kubectl, helm, terraform installed
- NVIDIA GPU-enabled nodes (recommended)

### Deployment

1. **Clone the repository**
```bash
git clone https://github.com/Liberty911/MLOps-Platform-for-LLM-Deployment.git
cd MLOps-Platform-for-LLM-Deployment