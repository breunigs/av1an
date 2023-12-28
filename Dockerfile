FROM archlinux:base-devel AS base

RUN pacman -Syu --noconfirm

# Install dependancies needed by all steps including runtime step
RUN pacman -S --noconfirm --needed aom ffmpeg vapoursynth ffms2 libvpx mkvtoolnix-cli svt-av1 vapoursynth-plugin-lsmashsource vmaf


FROM base AS build-base

# Install dependancies needed by build steps
RUN pacman -S --noconfirm --needed rust clang nasm git

RUN cargo install cargo-chef
WORKDIR /tmp/Av1an


FROM build-base AS planner

COPY . .
RUN cargo chef prepare


FROM build-base AS build

COPY --from=planner /tmp/Av1an/recipe.json recipe.json
RUN cargo chef cook --release

# Compile rav1e from git, as archlinux is still on rav1e 0.4
RUN git clone https://github.com/xiph/rav1e && \
    cd rav1e && \
    cargo build --release && \
    strip ./target/release/rav1e && \
    mv ./target/release/rav1e /usr/local/bin && \
    cd .. && rm -rf ./rav1e

# Build av1an
COPY . /tmp/Av1an

RUN cargo build --release && \
    mv ./target/release/av1an /usr/local/bin && \
    cd .. && rm -rf ./Av1an

# Create user
RUN useradd -ms /bin/bash build_user
RUN echo "%build_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/build_user
USER build_user

RUN \
  git clone https://aur.archlinux.org/vapoursynth-plugin-bestsource-git.git /tmp/bestsource \
  && cd /tmp/bestsource \
  && makepkg --syncdeps --noconfirm \
  && mv /tmp/bestsource/vapoursynth-plugin-bestsource-git-r*.pkg.tar.zst /bestsource.tar.zst

FROM base AS runtime

ENV MPLCONFIGDIR="/home/app_user/"

COPY --from=build /usr/local/bin/rav1e /usr/local/bin/rav1e
COPY --from=build /usr/local/bin/av1an /usr/local/bin/av1an
COPY --from=build /tmp/bestsource.tar.zst /
RUN tar --zstd -xf /bestsource.tar.zst -C / && rm /tmp/bestsource.tar.zst

# Create user
RUN useradd -ms /bin/bash app_user
USER app_user

VOLUME ["/videos"]
WORKDIR /videos

ENTRYPOINT [ "/usr/local/bin/av1an" ]
