FROM archlinux:latest

# Install official packages (aurutils is NOT in official repos — built below)
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel \
        git \
        devtools \
        sudo && \
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

USER root
COPY pacman.conf /etc/pacman.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    mkdir -p /repo && chown builder:builder /repo

VOLUME ["/repo"]

USER builder
WORKDIR /home/builder

ENTRYPOINT ["/entrypoint.sh"]
