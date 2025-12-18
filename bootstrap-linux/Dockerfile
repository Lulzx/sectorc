# Dockerfile for testing the trustworthy bootstrap chain
# Build: docker build -t bootstrap-test .
# Run:   docker run --rm bootstrap-test

FROM i386/debian:bullseye-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    xxd \
    binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /bootstrap

COPY stage0.hex stage1.hex stage2.hex hello.s2 cc.s2 bootstrap.sh test-docker.sh ./

RUN chmod +x bootstrap.sh test-docker.sh

CMD ["./bootstrap.sh"]
