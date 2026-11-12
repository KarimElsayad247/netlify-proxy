# Purpose: minimal image running the usque WARP/MASQUE client in the host network
# namespace. Uses the prebuilt release binary; no Go toolchain required.
FROM alpine:3.21 AS fetch

ARG USQUE_VERSION=4.2.1
ARG TARGETARCH=amd64

RUN apk add --no-cache curl unzip \
 && mkdir -p /out \
 && curl -fsSL -o /tmp/usque.zip \
      "https://github.com/Diniboy1123/usque/releases/download/v${USQUE_VERSION}/usque_${USQUE_VERSION}_linux_${TARGETARCH}.zip" \
 && unzip -o -q /tmp/usque.zip -d /out usque \
 && chmod 0755 /out/usque


FROM alpine:3.21

# iproute2 is required by the route hook; ca-certificates for the TLS endpoint.
RUN apk add --no-cache iproute2 ca-certificates

COPY --from=fetch /out/usque /usr/local/bin/usque
COPY hooks/up.sh /usr/local/bin/usque-up.sh
RUN chmod 0755 /usr/local/bin/usque /usr/local/bin/usque-up.sh \
 && [ "$(head -c 2 /usr/local/bin/usque-up.sh)" = '#!' ] \
 && echo "hook shebang present"

ENV ROUTES_FILE=/etc/usque-routes/netlify-ips.txt

ENTRYPOINT ["/usr/local/bin/usque"]
