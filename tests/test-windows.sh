#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# shellcheck source=../config.env
source "${PROJECT_DIR}/config.env"
# shellcheck disable=SC2034
LOG_FILE=""
# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"
# shellcheck source=../scripts/windows-templates.sh
source "${PROJECT_DIR}/scripts/windows-templates.sh"

WIN_ADMIN_USER='Admin&Ops'
WIN_ADMIN_PASSWORD='P<&>"Q'
xml_file="${TEST_DIR}/autounattend.xml"
generate_autounattend_xml 2022 "$xml_file"

[[ "$(stat -c '%a' "$xml_file")" == "600" ]]
python3 - "$xml_file" "$WIN_ADMIN_USER" "$WIN_ADMIN_PASSWORD" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, expected_user, expected_password = sys.argv[1:]
root = ET.parse(path).getroot()
texts = [(node.tag.rsplit('}', 1)[-1], node.text or '') for node in root.iter()]
assert ('Username', expected_user) in texts
assert sum(1 for tag, text in texts if tag == 'Value' and text == expected_password) == 2
PY

qm() {
    printf '%s\n' "$*" >> "${TEST_DIR}/qm.log"
    return 0
}

set +e
finalize_windows_template 123 >/dev/null 2>&1
invalid_rc=$?
set -e
if [[ "$invalid_rc" -eq 0 ]]; then
    echo 'ERRO: finalize-windows deveria rejeitar VMID não configurado.' >&2
    exit 1
fi
if [[ -s "${TEST_DIR}/qm.log" ]]; then
    echo 'ERRO: finalize-windows executou qm para um VMID não permitido.' >&2
    cat "${TEST_DIR}/qm.log" >&2
    exit 1
fi

cat > "${TEST_DIR}/pvesh" <<'MOCK'
#!/usr/bin/env bash
if [[ "${MOCK_INVENTORY_FAILURE:-0}" == 1 ]]; then
    exit 1
fi
printf '%s\n' '[{"vmid":9007,"name":"win-server-2022-template","node":"pve01","template":0,"type":"qemu"}]'
MOCK
chmod +x "${TEST_DIR}/pvesh"
PATH="${TEST_DIR}:${PATH}"
export PATH
# shellcheck disable=SC2034
PVE_MAJOR_VERSION=9

qm() {
    case "$1" in
        status) printf '%s\n' 'status: stopped' ;;
        config)
            printf '%s\n' 'name: win-server-2022-template'
            if [[ "${MOCK_EXTRA_TAG:-0}" == 1 ]]; then
                printf '%s\n' 'tags: template;cloudbase-init;windows;pve9;other'
            else
                printf '%s\n' 'tags: template;cloudbase-init;windows;pve9'
            fi
            if [[ "${MOCK_WRONG_ISO:-0}" == 1 ]]; then
                printf '%s\n' 'ide1: local:iso/other-autounattend-2022.iso,media=cdrom,size=1M'
            else
                printf '%s\n' 'ide1: local:iso/autounattend-2022.iso,media=cdrom,size=1M'
            fi
            ;;
        set|template) printf '%s\n' "$*" >> "${TEST_DIR}/mutation.log" ;;
        *) return 1 ;;
    esac
}

set +e
MOCK_WRONG_ISO=1 finalize_windows_template 9007 >/dev/null 2>&1
wrong_iso_rc=$?
set -e
if [[ "$wrong_iso_rc" -eq 0 || -s "${TEST_DIR}/mutation.log" ]]; then
    echo 'ERRO: finalize-windows aceitou um volume ISO diferente do esperado.' >&2
    exit 1
fi

set +e
MOCK_EXTRA_TAG=1 finalize_windows_template 9007 >/dev/null 2>&1
extra_tag_rc=$?
set -e
if [[ "$extra_tag_rc" -eq 0 || -s "${TEST_DIR}/mutation.log" ]]; then
    echo 'ERRO: finalize-windows aceitou um conjunto de tags diferente do esperado.' >&2
    exit 1
fi

set +e
MOCK_INVENTORY_FAILURE=1 finalize_windows_template 9007 >/dev/null 2>&1
inventory_failure_rc=$?
set -e
if [[ "$inventory_failure_rc" -eq 0 || -s "${TEST_DIR}/mutation.log" ]]; then
    echo 'ERRO: finalize-windows não falhou fechado com inventário indisponível.' >&2
    exit 1
fi

printf '%s\n' 'TEST_WINDOWS_OK'
