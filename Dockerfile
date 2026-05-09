FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel \
        git \
        aurutils \
        devtools \
        sudo && \
    pacman-key --init && \
    pacman-key --populate && \
    pacman -Scc --noconfirm

RUN useradd -m -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 440 /etc/sudoers.d/builder

COPY pacman.conf /etc/pacman.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /repo && chown builder:builder /repo

VOLUME ["/repo"]

USER builder
WORKDIR /home/builder

ENTRYPOINT ["/entrypoint.sh"]
