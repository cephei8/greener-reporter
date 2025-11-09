FROM nixos/nix:latest

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /workspace
COPY . .

ARG TARGETS=""

RUN nix flake check
RUN ./scripts/ci-build.sh
