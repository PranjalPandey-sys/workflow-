# =============================================================================
# Production Dockerfile for self-hosted n8n
# =============================================================================
# DECISION: extend n8n's official image rather than build n8n from source.
# n8n GmbH maintains this image (base OS patches, Node.js version, task-runner
# setup) far better than a hand-rolled build could. We add nothing that isn't
# strictly needed, which keeps the attack surface small and upgrades easy
# (bump one line, rebuild).
#
# DECISION: use the docker.n8n.io registry path. This is the path n8n's own
# docs currently document for pulls (mirrors n8nio/n8n on Docker Hub).
#
# VERSION PINNING (read before deploying to real production):
# "latest" is used below so your first deploy just works. Before you rely on
# this for anything important, pin to an explicit version, e.g.:
#   FROM docker.n8n.io/n8nio/n8n:1.XX.X
# ... using the exact tag you see at https://hub.docker.com/r/n8nio/n8n/tags
# Unpinned "latest" means a new n8n release can change your running instance
# on your NEXT rebuild without you choosing that upgrade.
FROM docker.io/n8nio/n8n:2.31.2

# The base image already runs as a non-root "node" user and sets its own
# WORKDIR/entrypoint. We deliberately do not override USER, ENTRYPOINT, or
# CMD -- inheriting those is what keeps this image secure by default.

# -----------------------------------------------------------------------------
# OPTIONAL: bake in community nodes at build time.
# Only uncomment this if you need a community node available immediately at
# container start, instead of installing it later from the editor UI
# (Settings > Community Nodes). Baking in at build time means the node
# survives a full redeploy without you re-installing it by hand.
# -----------------------------------------------------------------------------
# USER root
# RUN npm install -g n8n-nodes-<your-community-package>
# USER node

EXPOSE 5678

# Health check hits n8n's built-in health endpoint. Render (and most
# platforms) can use a Dockerfile HEALTHCHECK as an extra signal on top of
# their own HTTP health check (configured separately in render.yaml).
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider "http://127.0.0.1:${N8N_PORT:-5678}/healthz" || exit 1
