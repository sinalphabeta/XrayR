# Build go
FROM golang:1.23.1-alpine AS builder
WORKDIR /app
COPY . .
ENV CGO_ENABLED=0
RUN go mod download \
    && go build -v -o XrayR -trimpath -ldflags "-s -w -buildid="

# Release
FROM alpine:latest
# 安装必要的工具包
RUN apk --update --no-cache add curl tzdata ca-certificates \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && mkdir /etc/XrayR/ \
    && curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        --retry-delay 2 --connect-timeout 15 \
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat" \
        --output /etc/XrayR/geoip.dat \
    && curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        --retry-delay 2 --connect-timeout 15 \
        "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat" \
        --output /etc/XrayR/geosite.dat \
    && test -s /etc/XrayR/geoip.dat \
    && test -s /etc/XrayR/geosite.dat

COPY --from=builder /app/XrayR /usr/local/bin

ENTRYPOINT [ "XrayR", "--config", "/etc/XrayR/config.yml"]
