#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY="sinalphabeta/XrayR"
readonly INSTALL_URL="https://raw.githubusercontent.com/${REPOSITORY}/main/script/install.sh"
readonly MANAGER_URL="https://raw.githubusercontent.com/${REPOSITORY}/main/script/xrayr.sh"
readonly GEO_BASE="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release"
readonly CONFIG_DIR="/etc/XrayR"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yml"
readonly BINARY_FILE="/usr/local/XrayR/XrayR"
readonly SERVICE_NAME="XrayR.service"

die() {
    echo "错误: $*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "请使用 root 用户运行此命令"
}

require_installation() {
    [[ -x "${BINARY_FILE}" ]] || die "XrayR 尚未安装，请运行: XrayR install"
}

download() {
    local url=$1
    local destination=$2

    if ! curl --fail --location --silent --show-error \
        --retry 5 --retry-delay 2 --connect-timeout 15 \
        --output "${destination}" "${url}"; then
        echo "下载失败: ${url}" >&2
        return 1
    fi
    if [[ ! -s "${destination}" ]]; then
        echo "下载结果为空: ${url}" >&2
        return 1
    fi
}

run_installer() {
    local temp_file
    temp_file=$(mktemp)
    if ! download "${INSTALL_URL}" "${temp_file}"; then
        rm -f "${temp_file}"
        return 1
    fi
    local exit_code=0
    bash "${temp_file}" "$@" || exit_code=$?
    rm -f "${temp_file}"
    return "${exit_code}"
}

update_geo() {
    local temp_dir
    temp_dir=$(mktemp -d)

    if ! download "${GEO_BASE}/geoip.dat" "${temp_dir}/geoip.dat" || \
       ! download "${GEO_BASE}/geosite.dat" "${temp_dir}/geosite.dat"; then
        rm -rf "${temp_dir}"
        return 1
    fi

    install -d -m 0755 "${CONFIG_DIR}"
    install -m 0644 "${temp_dir}/geoip.dat" "${CONFIG_DIR}/geoip.dat"
    install -m 0644 "${temp_dir}/geosite.dat" "${CONFIG_DIR}/geosite.dat"
    rm -rf "${temp_dir}"

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl restart "${SERVICE_NAME}"
    fi
    echo "Geo 数据已更新"
}

update_manager() {
    local temp_file
    temp_file=$(mktemp /usr/bin/.XrayR.XXXXXX)
    if ! download "${MANAGER_URL}" "${temp_file}"; then
        rm -f "${temp_file}"
        return 1
    fi
    chmod 0755 "${temp_file}"
    mv -f "${temp_file}" /usr/bin/XrayR
    ln -sfn /usr/bin/XrayR /usr/bin/xrayr
    echo "管理脚本已更新"
}

edit_config() {
    local editor=${EDITOR:-vi}
    [[ -f "${CONFIG_FILE}" ]] || die "配置文件不存在: ${CONFIG_FILE}"
    "${editor}" "${CONFIG_FILE}"
    systemctl try-restart "${SERVICE_NAME}"
}

uninstall_xrayr() {
    local answer

    if [[ "${1:-}" != "--yes" ]]; then
        read -r -p "确认卸载 XrayR？配置目录 ${CONFIG_DIR} 将被保留 [y/N]: " answer
        [[ "${answer}" =~ ^[Yy]$ ]] || return 0
    fi

    systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
    rm -f /etc/systemd/system/XrayR.service
    rm -rf /usr/local/XrayR
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    echo "XrayR 已卸载，配置和管理命令仍然保留"
}

show_usage() {
    cat <<'EOF'
XrayR 管理命令

  XrayR install [version]  安装 XrayR，可指定 v1.0.0
  XrayR update [version]   更新 XrayR，默认使用最新版
  XrayR start              启动服务
  XrayR stop               停止服务
  XrayR restart            重启服务
  XrayR status             查看服务状态
  XrayR log                实时查看日志
  XrayR enable             设置开机自启
  XrayR disable            取消开机自启
  XrayR config             编辑配置并重启运行中的服务
  XrayR geo                更新 geoip.dat 和 geosite.dat
  XrayR version            查看 XrayR 版本
  XrayR update-shell       更新此管理脚本
  XrayR uninstall [--yes]  卸载程序并保留配置
EOF
}

main() {
    local command=${1:-help}
    shift || true

    case "${command}" in
        help | -h | --help)
            show_usage
            ;;
        install | update)
            require_root
            run_installer "$@"
            ;;
        start | stop | restart | enable | disable)
            require_root
            require_installation
            systemctl "${command}" "${SERVICE_NAME}"
            ;;
        status)
            require_installation
            systemctl status "${SERVICE_NAME}" --no-pager --full
            ;;
        log)
            require_installation
            journalctl --unit "${SERVICE_NAME}" --lines 100 --follow
            ;;
        config)
            require_root
            require_installation
            edit_config
            ;;
        geo)
            require_root
            require_installation
            update_geo
            ;;
        version)
            require_installation
            "${BINARY_FILE}" version
            ;;
        update-shell | update_shell)
            require_root
            update_manager
            ;;
        uninstall)
            require_root
            uninstall_xrayr "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
