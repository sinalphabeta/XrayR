#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY="sinalphabeta/XrayR"
readonly RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/main"
readonly GEO_BASE="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
readonly INSTALL_DIR="/usr/local/XrayR"
readonly CONFIG_DIR="/etc/XrayR"
readonly SERVICE_FILE="/etc/systemd/system/XrayR.service"
readonly MANAGER_FILE="/usr/bin/XrayR"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

log() {
    echo -e "${green}[XrayR]${plain} $*"
}

warn() {
    echo -e "${yellow}[XrayR]${plain} $*"
}

die() {
    echo -e "${red}[XrayR] $*${plain}" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "请使用 root 用户运行此脚本"
    [[ "$(uname -s)" == "Linux" ]] || die "一键安装脚本仅支持 Linux"
    command -v systemctl >/dev/null 2>&1 || die "当前系统未使用 systemd"
}

install_dependencies() {
    if command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
        return
    fi

    log "安装 curl 和 unzip"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl unzip
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl unzip
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install ca-certificates curl unzip
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm ca-certificates curl unzip
    else
        die "无法识别包管理器，请先安装 curl 和 unzip"
    fi
}

asset_name() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "linux-64" ;;
        i386 | i486 | i586 | i686) echo "linux-32" ;;
        aarch64 | arm64) echo "linux-arm64-v8a" ;;
        armv8l | armv7l | armv7) echo "linux-arm32-v7a" ;;
        armv6l | armv6) echo "linux-arm32-v6" ;;
        armv5l | armv5) echo "linux-arm32-v5" ;;
        mips64el | mips64le) echo "linux-mips64le" ;;
        mips64) echo "linux-mips64" ;;
        mipsel | mipsle) echo "linux-mips32le" ;;
        mips) echo "linux-mips32" ;;
        ppc64le) echo "linux-ppc64le" ;;
        riscv64) echo "linux-riscv64" ;;
        s390x) echo "linux-s390x" ;;
        *) die "不支持的系统架构: $(uname -m)" ;;
    esac
}

download() {
    local url=$1
    local destination=$2

    curl --fail --location --silent --show-error \
        --retry 5 --retry-delay 2 --connect-timeout 15 \
        --output "${destination}" "${url}"
    [[ -s "${destination}" ]] || die "下载结果为空: ${url}"
}

latest_version() {
    local release_url
    local version

    release_url=$(curl --fail --location --silent --show-error \
        --retry 5 --retry-delay 2 --connect-timeout 15 \
        --output /dev/null --write-out '%{url_effective}' \
        "https://github.com/${REPOSITORY}/releases/latest")
    version=${release_url##*/}
    [[ -n "${version}" ]] || die "无法获取最新版本，请手动指定版本，例如 v1.0.0"
    [[ "${version}" != "latest" ]] || die "仓库中还没有可用的 Release"
    echo "${version}"
}

normalize_version() {
    local requested=${1:-}

    if [[ -z "${requested}" || "${requested}" == "latest" ]]; then
        latest_version
    elif [[ "${requested}" == v* ]]; then
        echo "${requested}"
    else
        echo "v${requested}"
    fi
}

install_service() {
    cat > "${SERVICE_FILE}" <<'EOF'
[Unit]
Description=XrayR Service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/XrayR
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

main() {
    require_root
    install_dependencies

    local version
    local asset
    local archive
    local extract_dir
    local temp_dir
    local had_config=false
    local config_file

    version=$(normalize_version "${1:-}")
    asset=$(asset_name)
    temp_dir=$(mktemp -d)
    trap "rm -rf '${temp_dir}'" EXIT
    archive="${temp_dir}/XrayR.zip"
    extract_dir="${temp_dir}/release"

    log "下载 XrayR ${version} (${asset})"
    download \
        "https://github.com/${REPOSITORY}/releases/download/${version}/XrayR-${asset}.zip" \
        "${archive}"
    mkdir -p "${extract_dir}"
    unzip -q "${archive}" -d "${extract_dir}"
    [[ -f "${extract_dir}/XrayR" ]] || die "Release 压缩包中缺少 XrayR 可执行文件"

    log "下载 Geo 数据与管理脚本"
    download "${GEO_BASE}/geoip.dat" "${temp_dir}/geoip.dat"
    download "${GEO_BASE}/geosite.dat" "${temp_dir}/geosite.dat"
    download "${RAW_BASE}/script/xrayr.sh" "${temp_dir}/xrayr.sh"

    [[ -f "${CONFIG_DIR}/config.yml" ]] && had_config=true
    systemctl stop XrayR.service 2>/dev/null || true
    install -d -m 0755 "${INSTALL_DIR}" "${CONFIG_DIR}"
    install -m 0755 "${extract_dir}/XrayR" "${INSTALL_DIR}/XrayR"

    for config_file in config.yml dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ ! -e "${CONFIG_DIR}/${config_file}" && -f "${extract_dir}/${config_file}" ]]; then
            install -m 0644 "${extract_dir}/${config_file}" "${CONFIG_DIR}/${config_file}"
        fi
    done

    install -m 0644 "${temp_dir}/geoip.dat" "${CONFIG_DIR}/geoip.dat"
    install -m 0644 "${temp_dir}/geosite.dat" "${CONFIG_DIR}/geosite.dat"

    install -m 0755 "${temp_dir}/xrayr.sh" "${MANAGER_FILE}.new"
    mv -f "${MANAGER_FILE}.new" "${MANAGER_FILE}"
    ln -sfn "${MANAGER_FILE}" /usr/bin/xrayr

    install_service
    systemctl daemon-reload
    systemctl enable XrayR.service >/dev/null

    if [[ "${had_config}" == true ]]; then
        systemctl restart XrayR.service
        log "XrayR ${version} 安装完成并已启动"
    else
        warn "XrayR ${version} 安装完成，请先编辑 ${CONFIG_DIR}/config.yml"
        warn "配置完成后运行: XrayR start"
    fi

    echo "管理命令: XrayR help"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
