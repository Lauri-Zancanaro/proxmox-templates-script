#!/usr/bin/env bash
# =============================================================================
# utils.sh - Funções utilitárias para os scripts de criação de templates
# =============================================================================
# Este arquivo contém funções de log, validação de dependências, verificação
# de VMID, detecção de versão do Proxmox VE e outras utilidades compartilhadas.
#
# Compatibilidade: Proxmox VE 8.x e 9.x
# =============================================================================

# Cores para output no terminal
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m' # No Color

# Variáveis globais de detecção de versão (preenchidas por detect_pve_version)
PVE_MAJOR_VERSION=""
PVE_MINOR_VERSION=""
PVE_FULL_VERSION=""
QEMU_MAJOR_VERSION=""
QEMU_FULL_VERSION=""

# =============================================================================
# FUNÇÕES DE LOG
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Mapeamento de níveis para filtragem
    local current_num=1
    local msg_num=1

    case "${LOG_LEVEL:-INFO}" in
        DEBUG) current_num=0 ;; INFO) current_num=1 ;; WARN) current_num=2 ;; ERROR) current_num=3 ;;
    esac
    case "$level" in
        DEBUG) msg_num=0 ;; INFO) msg_num=1 ;; WARN) msg_num=2 ;; ERROR) msg_num=3 ;;
    esac

    # Só exibe se o nível da mensagem for >= nível configurado
    if [[ $msg_num -ge $current_num ]]; then
        local color=""
        case "$level" in
            DEBUG) color="$COLOR_CYAN"   ;;
            INFO)  color="$COLOR_GREEN"  ;;
            WARN)  color="$COLOR_YELLOW" ;;
            ERROR) color="$COLOR_RED"    ;;
        esac

        # Saída no terminal
        echo -e "${color}[${timestamp}] [${level}]${COLOR_NC} ${message}"

        # Saída no arquivo de log (sem cores)
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE" 2>/dev/null
        fi
    fi
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# =============================================================================
# DETECÇÃO DE VERSÃO DO PROXMOX VE
# =============================================================================

# Detecta a versão do Proxmox VE e do QEMU instalados.
# Preenche as variáveis globais PVE_MAJOR_VERSION, PVE_MINOR_VERSION,
# PVE_FULL_VERSION, QEMU_MAJOR_VERSION e QEMU_FULL_VERSION.
detect_pve_version() {
    # Detectar versão do PVE
    if command -v pveversion &>/dev/null; then
        PVE_FULL_VERSION=$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "")
        if [[ -n "$PVE_FULL_VERSION" ]]; then
            PVE_MAJOR_VERSION=$(echo "$PVE_FULL_VERSION" | cut -d'.' -f1)
            PVE_MINOR_VERSION=$(echo "$PVE_FULL_VERSION" | cut -d'.' -f2)
        fi
    fi

    # Fallback: detectar via pacote
    if [[ -z "$PVE_MAJOR_VERSION" ]]; then
        PVE_FULL_VERSION=$(dpkg -l pve-manager 2>/dev/null | awk '/^ii/ {print $3}' | grep -oP '^[0-9]+\.[0-9]+' || echo "")
        if [[ -n "$PVE_FULL_VERSION" ]]; then
            PVE_MAJOR_VERSION=$(echo "$PVE_FULL_VERSION" | cut -d'.' -f1)
            PVE_MINOR_VERSION=$(echo "$PVE_FULL_VERSION" | cut -d'.' -f2)
        fi
    fi

    # Detectar versão do QEMU
    if command -v qm &>/dev/null; then
        QEMU_FULL_VERSION=$(qm showcmd 0 2>/dev/null | grep -oP 'qemu-system-x86_64.*?-version\s+\K[0-9]+\.[0-9]+' || echo "")
        # Fallback: usar kvm --version
        if [[ -z "$QEMU_FULL_VERSION" ]] && command -v kvm &>/dev/null; then
            QEMU_FULL_VERSION=$(kvm --version 2>/dev/null | grep -oP 'QEMU.*version\s+\K[0-9]+\.[0-9]+' || echo "")
        fi
        if [[ -n "$QEMU_FULL_VERSION" ]]; then
            QEMU_MAJOR_VERSION=$(echo "$QEMU_FULL_VERSION" | cut -d'.' -f1)
        fi
    fi

    # Validar que a versão detectada é suportada
    if [[ -n "$PVE_MAJOR_VERSION" ]]; then
        if [[ "$PVE_MAJOR_VERSION" -lt 8 ]]; then
            log_error "Proxmox VE ${PVE_FULL_VERSION} detectado. Este script requer PVE 8.x ou 9.x."
            exit 1
        fi
        log_info "Proxmox VE ${PVE_FULL_VERSION} detectado (major: ${PVE_MAJOR_VERSION})."
    else
        log_warn "Não foi possível detectar a versão do Proxmox VE. Assumindo PVE 8.x."
        PVE_MAJOR_VERSION="8"
        PVE_MINOR_VERSION="0"
        PVE_FULL_VERSION="8.0"
    fi

    if [[ -n "$QEMU_FULL_VERSION" ]]; then
        log_info "QEMU ${QEMU_FULL_VERSION} detectado."
    else
        log_debug "Não foi possível detectar a versão do QEMU."
    fi

    # Exportar para subshells
    export PVE_MAJOR_VERSION PVE_MINOR_VERSION PVE_FULL_VERSION
    export QEMU_MAJOR_VERSION QEMU_FULL_VERSION
}

# Verifica se a versão do PVE é >= a uma versão mínima.
# Uso: pve_version_ge 9 0  (retorna 0 se PVE >= 9.0)
pve_version_ge() {
    local req_major="${1:-8}"
    local req_minor="${2:-0}"
    local cur_major="${PVE_MAJOR_VERSION:-8}"
    local cur_minor="${PVE_MINOR_VERSION:-0}"

    if [[ "$cur_major" -gt "$req_major" ]]; then
        return 0
    elif [[ "$cur_major" -eq "$req_major" ]] && [[ "$cur_minor" -ge "$req_minor" ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# FUNÇÕES DE VALIDAÇÃO
# =============================================================================

# Verifica se o script está sendo executado como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (ou com sudo)."
        exit 1
    fi
}

# Verifica se estamos em um nó Proxmox VE
check_proxmox() {
    if ! command -v qm &>/dev/null; then
        log_error "Comando 'qm' não encontrado. Este script deve ser executado em um nó Proxmox VE."
        exit 1
    fi

    if ! command -v pvesh &>/dev/null; then
        log_error "Comando 'pvesh' não encontrado. Este script deve ser executado em um nó Proxmox VE."
        exit 1
    fi

    log_info "Ambiente Proxmox VE detectado."
}

# Verifica se as dependências necessárias estão instaladas
check_dependencies() {
    local deps=("wget" "qm" "pvesh")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependências faltando: ${missing[*]}"
        log_error "Instale as dependências antes de continuar."
        exit 1
    fi

    log_info "Todas as dependências verificadas com sucesso."
}

# Verifica dependências adicionais para templates Windows
check_windows_dependencies() {
    local deps=("genisoimage")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Dependências para templates Windows faltando: ${missing[*]}"
        log_info "Tentando instalar automaticamente..."
        if ! apt-get update -qq && apt-get install -y -qq genisoimage; then
            log_error "Falha ao instalar dependências para Windows. Instale manualmente: apt install genisoimage"
            return 1
        fi
    fi

    log_info "Dependências para templates Windows verificadas."
    return 0
}

# Verifica se o storage pool existe no Proxmox e se é compatível
check_storage() {
    local storage="$1"

    if ! pvesm status | grep -q "^${storage} "; then
        log_error "Storage pool '${storage}' não encontrado no Proxmox."
        log_error "Storages disponíveis:"
        pvesm status | awk 'NR>1 {print "  - " $1}'
        exit 1
    fi

    # Verificar se o storage é GlusterFS (removido no PVE 9)
    local storage_type
    storage_type=$(pvesm status | awk -v s="$storage" '$1 == s {print $2}')
    if [[ "$storage_type" == "glusterfs" ]] && pve_version_ge 9 0; then
        log_error "Storage '${storage}' é do tipo GlusterFS, que foi removido no Proxmox VE 9."
        log_error "Migre seus dados para outro tipo de storage antes de continuar."
        exit 1
    fi

    log_info "Storage pool '${storage}' verificado com sucesso (tipo: ${storage_type})."
}

# Verifica se um VMID já está em uso
check_vmid_available() {
    local vmid="$1"

    if qm status "$vmid" &>/dev/null; then
        log_warn "VMID ${vmid} já está em uso."
        return 1
    fi

    log_debug "VMID ${vmid} está disponível."
    return 0
}

# Verifica se um VMID já é um template existente
check_vmid_is_template() {
    local vmid="$1"

    if qm config "$vmid" 2>/dev/null | grep -q "^template: 1"; then
        return 0
    fi

    return 1
}

# =============================================================================
# FUNÇÕES DE IMPORTAÇÃO DE DISCO (compatível PVE 8/9)
# =============================================================================

# Importa um disco de cloud image para uma VM.
# Em PVE 8.1+ e PVE 9.x usa a sintaxe import-from do qm set.
# Em PVE 8.0 usa o comando legado qm importdisk + qm set.
import_disk_image() {
    local vmid="$1"
    local image_path="$2"
    local storage="$3"
    local disk_bus="${4:-scsi0}"

    log_info "[VMID:${vmid}] Importando disco de '$(basename "$image_path")' para storage '${storage}'..."

    # PVE 8.1+ e PVE 9.x suportam import-from nativamente no qm set
    if pve_version_ge 8 1; then
        log_debug "Usando método import-from (PVE ${PVE_FULL_VERSION})..."
        if ! qm set "$vmid" --"${disk_bus}" "${storage}:0,import-from=${image_path},discard=on"; then
            log_error "[VMID:${vmid}] Falha ao importar disco via import-from."
            return 1
        fi
    else
        # Método legado para PVE 8.0
        log_debug "Usando método legado qm importdisk (PVE ${PVE_FULL_VERSION})..."
        if ! qm importdisk "$vmid" "$image_path" "$storage"; then
            log_error "[VMID:${vmid}] Falha ao importar disco via importdisk."
            return 1
        fi
        # Após importdisk, o disco fica como 'unused0'. Precisamos anexá-lo.
        if ! qm set "$vmid" --"${disk_bus}" "${storage}:vm-${vmid}-disk-0,discard=on"; then
            log_error "[VMID:${vmid}] Falha ao anexar disco importado."
            return 1
        fi
    fi

    log_info "[VMID:${vmid}] Disco importado com sucesso."
    return 0
}

# =============================================================================
# FUNÇÕES DE DOWNLOAD
# =============================================================================

# Faz download de um arquivo com verificação e retry
download_image() {
    local url="$1"
    local dest_dir="$2"
    local filename
    filename=$(basename "$url")
    local dest_path="${dest_dir}/${filename}"

    # Cria o diretório de destino se não existir
    mkdir -p "$dest_dir"

    # Verifica se o arquivo já existe
    if [[ -f "$dest_path" ]]; then
        log_info "Imagem '${filename}' já existe em '${dest_dir}'. Pulando download."
        echo "$dest_path"
        return 0
    fi

    log_info "Baixando '${filename}' de '${url}'..."
    log_info "Destino: ${dest_path}"

    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if wget -q --show-progress --progress=bar:force -O "$dest_path" "$url" 2>&1; then
            log_info "Download concluído: ${filename}"
            echo "$dest_path"
            return 0
        else
            retry=$((retry + 1))
            log_warn "Falha no download (tentativa ${retry}/${max_retries}). Aguardando 5s..."
            rm -f "$dest_path"
            sleep 5
        fi
    done

    log_error "Falha ao baixar '${filename}' após ${max_retries} tentativas."
    return 1
}

# =============================================================================
# FUNÇÕES DE TEMPLATE
# =============================================================================

# Remove um template existente (com confirmação)
remove_existing_template() {
    local vmid="$1"
    local name="$2"

    if check_vmid_available "$vmid"; then
        return 0
    fi

    if check_vmid_is_template "$vmid"; then
        log_warn "Template '${name}' (VMID: ${vmid}) já existe."
        log_info "Removendo template existente para recriação..."
        if qm destroy "$vmid" --purge 2>/dev/null; then
            log_info "Template anterior removido com sucesso."
            return 0
        else
            log_error "Falha ao remover template existente (VMID: ${vmid})."
            return 1
        fi
    else
        log_error "VMID ${vmid} está em uso por uma VM que NÃO é template. Abortando."
        log_error "Verifique o VMID e tente novamente."
        return 1
    fi
}

# =============================================================================
# FUNÇÕES DE EXIBIÇÃO
# =============================================================================

# Exibe um banner com informações do projeto
show_banner() {
    echo -e "${COLOR_CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           PROXMOX VE - Template Creation Script                ║"
    echo "║                                                                ║"
    echo "║  Criação automatizada de templates com Cloud-Init              ║"
    echo "║  Suporte: Ubuntu, Debian, CentOS, Rocky Linux, Windows Server  ║"
    echo "║  Compatível com Proxmox VE 8.x e 9.x                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_NC}"
}

# Exibe um resumo da configuração atual
show_config_summary() {
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo -e "${COLOR_BLUE}  CONFIGURAÇÃO ATUAL${COLOR_NC}"
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    printf "  %-25s %s\n" "Proxmox VE:" "${PVE_FULL_VERSION:-N/A}"
    printf "  %-25s %s\n" "QEMU:" "${QEMU_FULL_VERSION:-N/A}"
    printf "  %-25s %s\n" "Storage Pool:" "${STORAGE_POOL}"
    printf "  %-25s %s\n" "Bridge de Rede:" "${BRIDGE_NET}"
    printf "  %-25s %s\n" "Cloud-Init User:" "${CI_USER}"
    printf "  %-25s %s\n" "Cloud-Init Network:" "${CI_NETWORK}"
    printf "  %-25s %s\n" "QEMU Guest Agent:" "${ENABLE_QEMU_AGENT}"
    printf "  %-25s %s\n" "Log Level:" "${LOG_LEVEL}"
    printf "  %-25s %s\n" "Log File:" "${LOG_FILE}"
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo ""
}

# Exibe a tabela de templates que serão criados
show_template_table() {
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo -e "${COLOR_BLUE}  TEMPLATES A SEREM CRIADOS${COLOR_NC}"
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    printf "  %-8s %-35s %-10s\n" "VMID" "TEMPLATE" "TIPO"
    printf "  %-8s %-35s %-10s\n" "--------" "-----------------------------------" "----------"
    printf "  %-8s %-35s %-10s\n" "${VMID_UBUNTU_2404}" "ubuntu-2404-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_DEBIAN_12}" "debian-12-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_DEBIAN_13}" "debian-13-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_CENTOS_STREAM_9}" "centos-stream9-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ROCKY_8}" "rocky-8-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ROCKY_9}" "rocky-9-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_WIN_2022}" "win-server-2022-template" "Windows"
    printf "  %-8s %-35s %-10s\n" "${VMID_WIN_2025}" "win-server-2025-template" "Windows"
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo ""
}

# Exibe resultado final após criação dos templates
show_results() {
    local created=("$@")

    echo ""
    echo -e "${COLOR_GREEN}╔══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_GREEN}║                    RESULTADO DA EXECUÇÃO                        ║${COLOR_NC}"
    echo -e "${COLOR_GREEN}╚══════════════════════════════════════════════════════════════════╝${COLOR_NC}"

    if [[ ${#created[@]} -gt 0 ]]; then
        echo -e "${COLOR_GREEN}  Templates criados com sucesso:${COLOR_NC}"
        for item in "${created[@]}"; do
            echo -e "    ${COLOR_GREEN}✓${COLOR_NC} ${item}"
        done
    else
        echo -e "${COLOR_YELLOW}  Nenhum template foi criado.${COLOR_NC}"
    fi

    echo ""
    echo -e "${COLOR_BLUE}  Para clonar um template:${COLOR_NC}"
    echo "    qm clone <VMID_TEMPLATE> <NOVO_VMID> --name <nome-da-vm>"
    echo ""
    echo -e "${COLOR_BLUE}  Para configurar o clone:${COLOR_NC}"
    echo "    qm set <NOVO_VMID> --ipconfig0 ip=10.0.0.100/24,gw=10.0.0.1"
    echo "    qm set <NOVO_VMID> --sshkeys ~/.ssh/id_rsa.pub"
    echo ""
}
