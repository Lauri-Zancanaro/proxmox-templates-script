#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCK_DIR="$(mktemp -d)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR" "$TEST_DIR"' EXIT

cat > "${MOCK_DIR}/pvesh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *'/storage/storage-nvme'* ]]; then
    printf '%s\n' '{"content":"iso,snippets","type":"cephfs"}'
elif [[ "$*" == *'/cluster/resources'* ]]; then
    if [[ "${MOCK_API_FAILURE:-0}" == 1 ]]; then
        exit 1
    fi
    if [[ "${MOCK_INVALID_JSON:-0}" == 1 ]]; then
        printf '%s\n' 'not-json-success'
        exit 0
    fi
    printf '%s\n' '[{"vmid":9001,"name":"ubuntu-2404-template","node":"pve01","template":1,"type":"qemu"}]'
else
    exit 1
fi
MOCK

cat > "${MOCK_DIR}/pvesm" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    status)
        printf '%s\n' 'Name Type Status Total Used Available %'
        printf '%s\n' 'vm-nvme rbd active 1000 10 990 1%'
        printf '%s\n' 'storage-nvme cephfs active 1000 10 990 1%'
        ;;
    path)
        printf '%s\n' '/mnt/pve/storage-nvme/snippets/.proxmox-templates-preflight'
        ;;
    *) exit 1 ;;
esac
MOCK

cat > "${MOCK_DIR}/qm" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    importdisk)
        printf '%s\n' 'successfully imported disk as unused0: vm-nvme:vm-9002-disk-7'
        ;;
    config)
        printf '%s\n' 'unused0: vm-nvme:vm-9002-disk-7'
        ;;
    set)
        printf '%s\n' "$*" > "${MOCK_QM_LOG}"
        ;;
    status)
        exit 1
        ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "${MOCK_DIR}"/*

# shellcheck source=../config.env
source "${PROJECT_DIR}/config.env"
# shellcheck disable=SC2034
LOG_FILE=""
# shellcheck source=../scripts/utils.sh
source "${PROJECT_DIR}/scripts/utils.sh"
PATH="${MOCK_DIR}:${PATH}"
export PATH

if check_vmid_available 9001; then
    echo 'ERRO: VMID 9001 deveria ser detectado como ocupado no cluster.' >&2
    exit 1
fi
check_vmid_available 9002

set +e
MOCK_API_FAILURE=1 check_vmid_available 9002
api_failure_rc=$?
set -e
if [[ "$api_failure_rc" -ne 2 ]]; then
    echo "ERRO: falha de API deveria retornar 2, retornou ${api_failure_rc}." >&2
    exit 1
fi

set +e
MOCK_INVALID_JSON=1 check_vmid_available 9002
invalid_json_rc=$?
set -e
if [[ "$invalid_json_rc" -ne 2 ]]; then
    echo "ERRO: JSON inválido deveria retornar 2, retornou ${invalid_json_rc}." >&2
    exit 1
fi

check_storage vm-nvme
check_snippets_storage storage-nvme

image="${TEST_DIR}/cloud-image.qcow2"
truncate -s 2M "$image"
MOCK_QM_LOG="${TEST_DIR}/qm-set.log"
export MOCK_QM_LOG
import_disk_image 9002 "$image" vm-nvme scsi0
grep -Fxq 'set 9002 --scsi0 vm-nvme:vm-9002-disk-7,discard=on' "$MOCK_QM_LOG"

printf '%s\n' 'TEST_UTILS_OK'
