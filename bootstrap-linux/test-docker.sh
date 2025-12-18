#!/bin/bash
# Test the bootstrap chain using Docker
# Run: ./test-docker.sh

set -e
cd "$(dirname "$0")"

echo "Building Docker image..."
docker build -t bootstrap-test .

echo ""
echo "Running bootstrap chain in Docker..."
docker run --rm bootstrap-test
