# OpenHuman — Deployment Guide

## Docker (local development)

```bash
cd deploy/docker
docker compose up -d
```

This starts:
- PostgreSQL (port 5432)
- Redis (port 6379)
- NATS JetStream (port 4222)

## Kubernetes (production)

```bash
kubectl apply -f deploy/k8s/namespace.yaml
# TODO: add deployments, services, configmaps, secrets
```

## Status

**Phase 1 — Skeleton only.**
