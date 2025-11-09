FROM nixos/nix:latest

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /workspace

COPY . .

ARG TARGETS=""

RUN nix flake check

RUN mkdir -p /output
RUN set -e; \
    if [ -z "$TARGETS" ]; then \
    nix build; \
    cp -r result/* /output/; \
    rm -f result; \
    else \
    for target in $TARGETS; do \
    nix build ".#$target"; \
    mkdir -p /output/$target; \
    cp -r result/* /output/$target/; \
    rm -f result; \
    done; \
    fi
