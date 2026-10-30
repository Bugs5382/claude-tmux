# A clean Ubuntu with systemd as PID 1, so the end-to-end check runs the real user timer.
# Pinned by digest (the multi-arch index) so the base never drifts; bump it on purpose.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session tmux jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# A plain user whose user manager starts at boot (lingering), as on a box someone logs into.
RUN useradd -m -s /bin/bash tester && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/tester
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
