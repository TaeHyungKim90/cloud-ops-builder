# BuildKit with corporate/Zscaler CA (for docker-container buildx driver).
# Host WSL CA는 buildkit 컨테이너에 자동 반영되지 않음 → 이 이미지로 빌더를 띄운다.
FROM moby/buildkit:buildx-stable-1

USER root
COPY certs/ /usr/local/share/ca-certificates/
# Alpine(buildkit) + Debian 둘 다 대응
RUN set -eux; \
    if command -v update-ca-certificates >/dev/null 2>&1; then \
      update-ca-certificates; \
    fi; \
    for f in /usr/local/share/ca-certificates/*.crt \
             /usr/local/share/ca-certificates/*.pem; do \
      [ -f "$f" ] || continue; \
      cat "$f" >> /etc/ssl/certs/ca-certificates.crt; \
    done
