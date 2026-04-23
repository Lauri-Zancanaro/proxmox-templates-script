#!/usr/bin/env bash
# =============================================================================
# utils.sh - Funções utilitárias para os scripts de criação de templates
# =============================================================================
# Este arquivo contém funções de log, validação de dependências, verificação
# de VMID e outras utilidades compartilhadas entre os scripts do projeto.
# =============================================================================

# Cores para output no terminal
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m' # No Color

# =============================================================================
# FUNÇÕES DE LOG
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Mapeamento de níveis numéricos para filtragem
    declare -A level_map=( ["DEBUG"]=0 ["INFO"]=1 ["WARN"]=2 ["ERROR"]=3 )
    local current_level=${level_map[${LOG_LEVEL:-INFO}]:-1}
    local msg_level=${level_map[$level]:-1}

    # Só exibe se o nível da mensagem for >= nível configurado
    if [[ $msg_level -ge $current_level ]]; then
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
        apt-get update -qq && apt-get install -y -qq genisoimage
        if [[ $? -ne 0 ]]; then
            log_error "Falha ao instalar dependências para Windows. Instale manualmente: apt install genisoimage"
            return 1
        fi
    fi

    log_info "Dependências para templates Windows verificadas."
    return 0
}

# Verifica se o storage pool existe no Proxmox
check_storage() {
    local storage="$1"

    if ! pvesm status | grep -q "^${storage} "; then
        log_error "Storage pool '${storage}' não encontrado no Proxmox."
        log_error "Storages disponíveis:"
        pvesm status | awk 'NR>1 {print "  - " $1}'
        exit 1
    fi

    log_info "Storage pool '${storage}' verificado com sucesso."
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
        qm destroy "$vmid" --purge 2>/dev/null
        if [[ $? -eq 0 ]]; then
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
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_NC}"
}

# Exibe um resumo da configuração atual
show_config_summary() {
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo -e "${COLOR_BLUE}  CONFIGURAÇÃO ATUAL${COLOR_NC}"
    echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
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
