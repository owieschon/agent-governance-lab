# Minimal image for the OS-isolation boundary (see isolate/run.sh).
# It carries only what the trust layer needs to run -- git, bash, python3 --
# plus your agent's own runtime, which you add. The boundary is the read-only
# mounts and --network=none that run.sh applies, NOT anything in this image.
FROM python:3-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Add your agent runtime here if you run the loop inside the container, e.g.
# Node + the Claude Code CLI. Left out by default so the image stays minimal
# and the boundary (read-only trust layer + no network) is the whole point.

WORKDIR /work
CMD ["bash"]
