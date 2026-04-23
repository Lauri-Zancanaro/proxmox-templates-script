#!/usr/bin/env bash
# =============================================================================
# linux-templates.sh - Criação de templates Linux com Cloud-Init
# =============================================================================
# Este script contém as funções para download de cloud images e criação de
# templates Linux no Proxmox VE com suporte a Cloud-Init.
#
# Compatibilidade: Proxmox VE 8.x e 9.x
#
# Distribuições suportadas:
#   - Ubuntu 24.04 LTS (Noble Numbat)
#   - Debian 12 (Bookworm)
#   - Debian 13 (Trixie)
#   - CentOS Stream 9
#   - Rocky Linux 8
#   - Rocky Linux 9
#
# Referências:
#   - https://pve.proxmox.com/wiki/Cloud-Init_Support
#   - https://pve.proxmox.com/pve-docs/qm.1.html
# =============================================================================

# =============================================================================
# FUNÇÃO PRINCIPAL: Criar template Linux genérico
# =============================================================================
# Argumentos:
#   $1 - VMID do template
#   $2 - Nome do template
#   $3 - URL da cloud image
#   $4 - Tipo de OS (l26 para Linux 2.6+)
#   $5 - Descrição do template
# =============================================================================
create_linux_template() {
    local vmid="$1"
    local name="$2"
    local image_url="$3"
    local ostype="${4:-l26}"
    local description="${5:-Template criado automaticamente}"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Iniciando criação do template: ${name} (VMID: ${vmid})"
    log_info "Proxmox VE: ${PVE_FULL_VERSION:-N/A} | QEMU: ${QEMU_FULL_VERSION:-N/A}"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # -------------------------------------------------------------------------
    # Passo 1: Verificar e preparar VMID
    # -------------------------------------------------------------------------
    if ! remove_existing_template "$vmid" "$name"; then
        log_error "Não foi possível preparar o VMID ${vmid}. Pulando '${name}'."
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 2: Download da cloud image
    # -------------------------------------------------------------------------
    local image_path
    image_path=$(download_image "$image_url" "$DOWNLOAD_DIR")
    if [[ $? -ne 0 ]] || [[ -z "$image_path" ]]; then
        log_error "Falha no download da imagem para '${name}'. Pulando."
        return 1
    fi

    local image_file
    image_file=$(basename "$image_path")

    # -------------------------------------------------------------------------
    # Passo 3: Criar a VM base
    # -------------------------------------------------------------------------
    log_info "[${name}] Criando VM base (VMID: ${vmid})..."

    # Montar o comando base de criação da VM
    local create_args=(
        "$vmid"
        --name "$name"
        --ostype "$ostype"
        --memory "$LINUX_MEMORY"
        --cores "$LINUX_CORES"
        --cpu host
        --net0 "virtio,bridge=${BRIDGE_NET}"
        --description "$description"
        --tags "template,cloud-init,linux,pve${PVE_MAJOR_VERSION:-8}"
    )

    if ! qm create "${create_args[@]}"; then
        log_error "[${name}] Falha ao criar a VM base."
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 4: Importar o disco da cloud image (compatível PVE 8/9)
    # -------------------------------------------------------------------------
    if ! import_disk_image "$vmid" "$image_path" "$STORAGE_POOL" "scsi0"; then
        log_error "[${name}] Falha ao importar o disco."
        qm destroy "$vmid" --purge 2>/dev/null
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 5: Configurar SCSI controller e boot
    # -------------------------------------------------------------------------
    log_info "[${name}] Configurando hardware (SCSI, boot, serial)..."
    qm set "$vmid" --scsihw virtio-scsi-pci
    qm set "$vmid" --boot order=scsi0 --bootdisk scsi0

    # -------------------------------------------------------------------------
    # Passo 6: Configurar serial console e VGA
    # -------------------------------------------------------------------------
    # A maioria das cloud images requer serial console para funcionar
    # corretamente. Se a imagem não funcionar com serial, remova estas linhas.
    qm set "$vmid" --serial0 socket --vga serial0

    # -------------------------------------------------------------------------
    # Passo 7: Adicionar drive Cloud-Init
    # -------------------------------------------------------------------------
    log_info "[${name}] Adicionando drive Cloud-Init..."
    if ! qm set "$vmid" --ide2 "${STORAGE_POOL}:cloudinit"; then
        log_error "[${name}] Falha ao adicionar drive Cloud-Init."
        qm destroy "$vmid" --purge 2>/dev/null
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 8: Habilitar QEMU Guest Agent
    # -------------------------------------------------------------------------
    if [[ "${ENABLE_QEMU_AGENT}" == "true" ]]; then
        log_info "[${name}] Habilitando QEMU Guest Agent..."
        local agent_opts="enabled=1"
        if [[ "${ENABLE_FSTRIM}" == "true" ]]; then
            agent_opts="enabled=1,fstrim_cloned_disks=1"
        fi
        qm set "$vmid" --agent "$agent_opts"
    fi

    # -------------------------------------------------------------------------
    # Passo 9: Configurar Cloud-Init (usuário, senha, rede)
    # -------------------------------------------------------------------------
    log_info "[${name}] Configurando Cloud-Init (usuário, rede)..."
    qm set "$vmid" --ciuser "$CI_USER"

    if [[ -n "$CI_PASSWORD" ]]; then
        qm set "$vmid" --cipassword "$CI_PASSWORD"
    fi

    if [[ -n "$CI_SSHKEY" ]] && [[ -f "$CI_SSHKEY" ]]; then
        log_info "[${name}] Configurando chave SSH: ${CI_SSHKEY}"
        qm set "$vmid" --sshkeys "$CI_SSHKEY"
    fi

    # Configuração de rede
    if [[ "$CI_NETWORK" == "static" ]] && [[ -n "$CI_IP" ]] && [[ -n "$CI_GW" ]]; then
        qm set "$vmid" --ipconfig0 "ip=${CI_IP}/${CI_MASK},gw=${CI_GW}"
        if [[ -n "$CI_DNS" ]]; then
            qm set "$vmid" --nameserver "$CI_DNS"
        fi
        if [[ -n "$CI_SEARCHDOMAIN" ]]; then
            qm set "$vmid" --searchdomain "$CI_SEARCHDOMAIN"
        fi
    else
        qm set "$vmid" --ipconfig0 "ip=dhcp"
    fi

    # -------------------------------------------------------------------------
    # Passo 10: Redimensionar disco (se configurado)
    # -------------------------------------------------------------------------
    if [[ -n "$LINUX_DISK_RESIZE" ]]; then
        log_info "[${name}] Redimensionando disco para ${LINUX_DISK_RESIZE}..."
        qm disk resize "$vmid" scsi0 "$LINUX_DISK_RESIZE" 2>/dev/null || \
            log_debug "[${name}] Disco já é maior que ${LINUX_DISK_RESIZE} (OK)."
    fi

    # -------------------------------------------------------------------------
    # Passo 11: Converter para template
    # -------------------------------------------------------------------------
    log_info "[${name}] Convertendo VM para template..."
    if ! qm template "$vmid"; then
        log_error "[${name}] Falha ao converter para template."
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 12: Limpeza (opcional)
    # -------------------------------------------------------------------------
    if [[ "${CLEANUP_IMAGES}" == "true" ]]; then
        log_info "[${name}] Removendo imagem baixada: ${image_file}"
        rm -f "$image_path"
    fi

    log_info "[${name}] Template criado com sucesso! (VMID: ${vmid})"
    echo ""
    return 0
}

# =============================================================================
# FUNÇÕES ESPECÍFICAS POR DISTRIBUIÇÃO
# =============================================================================

create_ubuntu_2404_template() {
    create_linux_template \
        "$VMID_UBUNTU_2404" \
        "ubuntu-2404-template" \
        "$URL_UBUNTU_2404" \
        "l26" \
        "Ubuntu 24.04 LTS (Noble Numbat) - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_debian_12_template() {
    create_linux_template \
        "$VMID_DEBIAN_12" \
        "debian-12-template" \
        "$URL_DEBIAN_12" \
        "l26" \
        "Debian 12 (Bookworm) - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_debian_13_template() {
    create_linux_template \
        "$VMID_DEBIAN_13" \
        "debian-13-template" \
        "$URL_DEBIAN_13" \
        "l26" \
        "Debian 13 (Trixie) - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_centos_stream9_template() {
    create_linux_template \
        "$VMID_CENTOS_STREAM_9" \
        "centos-stream9-template" \
        "$URL_CENTOS_STREAM_9" \
        "l26" \
        "CentOS Stream 9 - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_rocky_8_template() {
    create_linux_template \
        "$VMID_ROCKY_8" \
        "rocky-8-template" \
        "$URL_ROCKY_8" \
        "l26" \
        "Rocky Linux 8 - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_rocky_9_template() {
    create_linux_template \
        "$VMID_ROCKY_9" \
        "rocky-9-template" \
        "$URL_ROCKY_9" \
        "l26" \
        "Rocky Linux 9 - Cloud-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

# =============================================================================
# FUNÇÃO: Criar todos os templates Linux
# =============================================================================
create_all_linux_templates() {
    local created=()
    local failed=()

    log_info "Iniciando criação de TODOS os templates Linux..."
    echo ""

    # Ubuntu 24.04
    if create_ubuntu_2404_template; then
        created+=("ubuntu-2404-template (VMID: ${VMID_UBUNTU_2404})")
    else
        failed+=("ubuntu-2404-template (VMID: ${VMID_UBUNTU_2404})")
    fi

    # Debian 12
    if create_debian_12_template; then
        created+=("debian-12-template (VMID: ${VMID_DEBIAN_12})")
    else
        failed+=("debian-12-template (VMID: ${VMID_DEBIAN_12})")
    fi

    # Debian 13
    if create_debian_13_template; then
        created+=("debian-13-template (VMID: ${VMID_DEBIAN_13})")
    else
        failed+=("debian-13-template (VMID: ${VMID_DEBIAN_13})")
    fi

    # CentOS Stream 9
    if create_centos_stream9_template; then
        created+=("centos-stream9-template (VMID: ${VMID_CENTOS_STREAM_9})")
    else
        failed+=("centos-stream9-template (VMID: ${VMID_CENTOS_STREAM_9})")
    fi

    # Rocky Linux 8
    if create_rocky_8_template; then
        created+=("rocky-8-template (VMID: ${VMID_ROCKY_8})")
    else
        failed+=("rocky-8-template (VMID: ${VMID_ROCKY_8})")
    fi

    # Rocky Linux 9
    if create_rocky_9_template; then
        created+=("rocky-9-template (VMID: ${VMID_ROCKY_9})")
    else
        failed+=("rocky-9-template (VMID: ${VMID_ROCKY_9})")
    fi

    # Resumo
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "RESUMO - Templates Linux"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Criados com sucesso: ${#created[@]}"
    for item in "${created[@]}"; do
        log_info "  ✓ ${item}"
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warn "Falhas: ${#failed[@]}"
        for item in "${failed[@]}"; do
            log_warn "  ✗ ${item}"
        done
    fi

    echo ""

    # shellcheck disable=SC2034
    CREATED_LINUX_TEMPLATES=("${created[@]}")
    # shellcheck disable=SC2034
    FAILED_LINUX_TEMPLATES=("${failed[@]}")
}
