FROM nixos/nix:latest

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /workspace

COPY . .

ARG PACKAGE="default"

RUN nix build ".#${PACKAGE}"
RUN mkdir -p /output && cp -r result/* /output/
