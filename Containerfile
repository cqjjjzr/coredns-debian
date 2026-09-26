FROM docker.io/library/debian:13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential debhelper golang-any git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY build.sh /packaging/build.sh
COPY debian /packaging/debian
WORKDIR /out
ENTRYPOINT ["/packaging/build.sh", "--output", "/out"]
