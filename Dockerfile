# OKE — OpenKubes Kubernetes Engine
# Multi-arch image (amd64 + arm64)
# Binaries werden vom CI gebaut und hier nur eingebettet.
FROM scratch

ARG TARGETARCH
COPY dist/oke-linux-${TARGETARCH} /usr/local/bin/oke

ENTRYPOINT ["/usr/local/bin/oke"]
