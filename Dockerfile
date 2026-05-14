FROM archlinux:latest

# Install official packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel \
        git \
        devtools \
        sudo \
        curl && \
    rm -rf /var/cache/pacman/pkg/*

# Create build user (makepkg refuses to run as root)
RUN useradd -m -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 440 /etc/sudoers.d/builder

# Bootstrap aurutils from AUR
USER builder
RUN git clone https://aur.archlinux.org/aurutils.git /tmp/aurutils && \
    cd /tmp/aurutils && \
    makepkg -si --noconfirm && \
    rm -rf /tmp/aurutils

# Configure GPG to auto-fetch missing signing keys from keyserver
RUN mkdir -p /home/builder/.gnupg && \
    chmod 700 /home/builder/.gnupg && \
    echo "keyserver-options auto-key-retrieve" >> /home/builder/.gnupg/gpg.conf && \
    echo "keyserver hkps://keyserver.ubuntu.com" >> /home/builder/.gnupg/gpg.conf

USER root
COPY pacman.conf /etc/pacman.conf
COPY entrypoint.sh /entrypoint.sh
COPY build.sh /build.sh
RUN curl -sSLf \
        "https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64" \
        -o /usr/local/bin/supercronic && \
    chmod +x /usr/local/bin/supercronic && \
    mkdir -p /etc/aurutils && \
    cp /etc/pacman.conf /etc/aurutils/pacman-x86_64.conf && \
    chmod +x /entrypoint.sh /build.sh && \
    mkdir -p /repo && chown builder:builder /repo

VOLUME ["/repo"]

USER builder
WORKDIR /home/builder

ENTRYPOINT ["/entrypoint.sh"]
