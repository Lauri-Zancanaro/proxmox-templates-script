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
WINDOWS_ISO_STORAGE='iso-store'
export WINDOWS_ISO_STORAGE
DOWNLOAD_DIR="${TEST_DIR}/iso"
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

python3 - "$xml_file" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ns = {'u': 'urn:schemas-microsoft-com:unattend'}
mods = root.findall('.//u:DiskConfiguration/u:Disk/u:ModifyPartitions/u:ModifyPartition', ns)
layout = [
    (
        item.findtext('u:Order', namespaces=ns),
        item.findtext('u:PartitionID', namespaces=ns),
        item.findtext('u:Format', namespaces=ns),
        item.findtext('u:Letter', namespaces=ns),
    )
    for item in mods
]
assert layout == [('1', '1', 'FAT32', None), ('2', '3', 'NTFS', 'C')], layout
assert root.findtext('.//u:DiskConfiguration/u:WillShowUI', namespaces=ns) == 'OnError'
PY

xml_2019="${TEST_DIR}/autounattend-2019.xml"
generate_autounattend_xml 2019 "$xml_2019"
grep -Fq 'E:\vioscsi\2k19\amd64' "$xml_2019"
! grep -Fq 'E:\NetKVM\2k19\amd64' "$xml_2019"
! grep -Fq 'E:\Balloon\2k19\amd64' "$xml_2019"
! grep -Fq 'E:\viostor\2k19\amd64' "$xml_2019"
[[ "$(windows_virtio_driver_path 2019)" == '2k19' ]]
[[ "$(windows_ostype 2019)" == 'win10' ]]
[[ "$(windows_ostype 2022)" == 'win11' ]]
[[ "$(windows_evaluation_url 2019)" == 'https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019' ]]
if windows_ostype 2016 >/dev/null 2>&1; then
    echo 'ERRO: versão Windows não suportada foi aceita.' >&2
    exit 1
fi

[[ "$(windows_iso_volume 'windows-server-2019-eval.iso')" == 'iso-store:iso/windows-server-2019-eval.iso' ]]
if windows_iso_volume '../escape.iso' >/dev/null 2>&1; then
    echo 'ERRO: nome de ISO com caminho foi aceito.' >&2
    exit 1
fi

cat > "${TEST_DIR}/pvesm" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == path ]]; then
    printf '/srv/proxmox-iso/%s\n' "${2##*/}"
    exit 0
fi
exit 1
MOCK
chmod +x "${TEST_DIR}/pvesm"
PATH="${TEST_DIR}:${PATH}"
export PATH
[[ "$(windows_iso_host_path 'iso-store:iso/virtio-win.iso')" == '/srv/proxmox-iso/virtio-win.iso' ]]

(
    DOWNLOAD_DIR="${TEST_DIR}/iso-preflight"
    mkdir -p "$DOWNLOAD_DIR"
    : > "${DOWNLOAD_DIR}/windows-server-2019-eval.iso"
    : > "${DOWNLOAD_DIR}/virtio-win.iso"
    check_windows_dependencies() { return 0; }
    check_storage() { [[ "$1" == 'iso-store' ]]; }
    pvesm() {
        if [[ "$1" == path ]]; then
            printf '%s/%s\n' "$DOWNLOAD_DIR" "${2##*/}"
            return 0
        fi
        return 1
    }
    check_windows_prerequisites 2019
    [[ "$WIN_ISO_VOLUME" == 'iso-store:iso/windows-server-2019-eval.iso' ]]
    [[ "$VIRTIO_ISO_VOLUME" == 'iso-store:iso/virtio-win.iso' ]]
)

(
    mkdir -p "$DOWNLOAD_DIR"

    check_windows_prerequisites() {
        WIN_ISO_VOLUME='iso-store:iso/windows-server-2019-eval.iso'
        VIRTIO_ISO_VOLUME='iso-store:iso/virtio-win.iso'
        return 0
    }
    assert_vmid_available() { return 0; }
    windows_iso_host_path() {
        printf '%s/%s\n' "$DOWNLOAD_DIR" "${1##*/}"
    }
    generate_autounattend_iso() {
        : > "$2"
    }
    qm() {
        printf '%s\n' "$*" >> "${TEST_DIR}/qm-create.log"
        return 0
    }

    create_windows_template 9119 'win-server-2019-test' 2019 >/dev/null 2>&1
    grep -Fq -- '--ide0 iso-store:iso/windows-server-2019-eval.iso,media=cdrom' "${TEST_DIR}/qm-create.log"
    grep -Fq -- '--ide1 iso-store:iso/virtio-win.iso,media=cdrom' "${TEST_DIR}/qm-create.log"
    grep -Fq -- '--ide2 iso-store:iso/autounattend-2019.iso,media=cdrom' "${TEST_DIR}/qm-create.log"
)

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
printf '[{"vmid":%s,"name":"%s","node":"pve01","template":0,"type":"qemu"}]\n' \
    "${MOCK_VMID:-9007}" "${MOCK_NAME:-win-server-2022-template}"
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
            printf 'name: %s\n' "${MOCK_NAME:-win-server-2022-template}"
            if [[ "${MOCK_EXTRA_TAG:-0}" == 1 ]]; then
                printf '%s\n' 'tags: template;cloudbase-init;windows;pve9;other'
            else
                printf '%s\n' 'tags: template;cloudbase-init;windows;pve9'
            fi
            if [[ "${MOCK_WRONG_ISO:-0}" == 1 ]]; then
                printf 'ide2: %s,media=cdrom,size=1M\n' "$(windows_iso_volume "other-autounattend-${MOCK_YEAR:-2022}.iso")"
            else
                printf 'ide2: %s,media=cdrom,size=1M\n' "$(windows_iso_volume "autounattend-${MOCK_YEAR:-2022}.iso")"
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

unset MOCK_INVENTORY_FAILURE MOCK_WRONG_ISO MOCK_EXTRA_TAG
# shellcheck disable=SC2034
VMID_WIN_2019=9112
export MOCK_VMID=9112
export MOCK_NAME='win-server-2019-template'
export MOCK_YEAR=2019
: > "${TEST_DIR}/mutation.log"
finalize_windows_template 9112 >/dev/null 2>&1
grep -Fq 'set 9112 --delete ide0' "${TEST_DIR}/mutation.log"
grep -Fq 'set 9112 --ide2 cephfs-lvm:cloudinit' "${TEST_DIR}/mutation.log"
grep -Fq 'set 9112 --boot order=scsi0' "${TEST_DIR}/mutation.log"
grep -Fq 'template 9112' "${TEST_DIR}/mutation.log"

printf '%s\n' 'TEST_WINDOWS_OK'
