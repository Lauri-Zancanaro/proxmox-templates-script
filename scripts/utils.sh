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

        # Saída no terminal (stderr para não poluir stdout de funções com retorno)
        echo -e "${color}[${timestamp}] [${level}]${COLOR_NC} ${message}" >&2

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
    local deps=("wget" "qm" "pvesh" "pvesm" "ip" "perl")
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
    local deps=("genisoimage" "isoinfo")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Dependências para templates Windows faltando: ${missing[*]}"
        log_info "Tentando instalar automaticamente..."
        if ! apt-get update -qq || ! apt-get install -y -qq genisoimage; then
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
    local storage_type storage_status
    storage_type=$(pvesm status | awk -v s="$storage" '$1 == s {print $2}')
    storage_status=$(pvesm status | awk -v s="$storage" '$1 == s {print $3}')
    if [[ "$storage_status" != "active" ]]; then
        log_error "Storage '${storage}' não está ativo (status: ${storage_status:-desconhecido})."
        exit 1
    fi
    if [[ "$storage_type" == "glusterfs" ]] && pve_version_ge 9 0; then
        log_error "Storage '${storage}' é do tipo GlusterFS, que foi removido no Proxmox VE 9."
        log_error "Migre seus dados para outro tipo de storage antes de continuar."
        exit 1
    fi

    log_info "Storage pool '${storage}' verificado com sucesso (tipo: ${storage_type})."
}

# Verifica se a bridge configurada existe e está ativa no nó atual.
check_bridge() {
    local bridge="$1"

    if ! ip link show "$bridge" &>/dev/null; then
        log_error "Bridge '${bridge}' não encontrada no nó atual."
        exit 1
    fi

    local state
    state=$(cat "/sys/class/net/${bridge}/operstate" 2>/dev/null || echo "unknown")
    if [[ "$state" != "up" && "$state" != "unknown" ]]; then
        log_error "Bridge '${bridge}' não está ativa (estado: ${state})."
        exit 1
    fi

    log_info "Bridge '${bridge}' verificada com sucesso (estado: ${state})."
}

# Valida um storage de snippets e resolve um volume de teste sem criar arquivos.
check_snippets_storage() {
    local storage="$1"
    check_storage "$storage"

    local storage_json
    if ! storage_json=$(pvesh get "/storage/${storage}" --output-format json 2>/dev/null); then
        log_error "Não foi possível consultar a configuração do storage de snippets '${storage}'."
        exit 1
    fi

    local storage_content
    storage_content=$(sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$storage_json")
    if [[ ",${storage_content}," != *,snippets,* ]]; then
        log_error "Storage '${storage}' não possui o content type 'snippets' habilitado."
        log_error "Habilite 'snippets' pela GUI ou revise: pvesm set ${storage} --content <tipos-atuais>,snippets"
        exit 1
    fi

    local test_path
    if ! test_path=$(pvesm path "${storage}:snippets/.proxmox-templates-preflight" 2>/dev/null); then
        log_error "Storage '${storage}' não conseguiu resolver um volume do tipo snippets."
        exit 1
    fi

    log_info "Storage de snippets '${storage}' validado (caminho: $(dirname "$test_path"))."
}

# Exibe a disponibilidade dos VMIDs configurados e falha se houver conflito.
check_configured_vmids() {
    local vmids=(
        "$VMID_UBUNTU_2404" "$VMID_UBUNTU_2604"
        "$VMID_DEBIAN_12" "$VMID_DEBIAN_13"
        "$VMID_CENTOS_STREAM_9" "$VMID_ROCKY_8" "$VMID_ROCKY_9"
        "$VMID_ORACLE_8" "$VMID_ORACLE_9"
        "$VMID_WIN_2019" "$VMID_WIN_2022" "$VMID_WIN_2025"
    )
    check_vmids_available "${vmids[@]}"
}

# Verifica uma lista de VMIDs no inventário global do cluster.
check_vmids_available() {
    local vmids=("$@")
    local conflicts=0 vmid check_rc

    log_info "Verificando VMIDs configurados no cluster..."
    for vmid in "${vmids[@]}"; do
        check_vmid_available "$vmid" && check_rc=0 || check_rc=$?
        case "$check_rc" in
            0) log_info "VMID ${vmid}: livre" ;;
            1)
                log_warn "VMID ${vmid}: OCUPADO no cluster"
                conflicts=$((conflicts + 1))
                ;;
            *)
                log_error "Falha ao validar VMID ${vmid}; abortando sem alterações."
                return 2
                ;;
        esac
    done

    if [[ "$conflicts" -gt 0 ]]; then
        log_error "Pré-flight encontrou ${conflicts} VMID(s) ocupado(s). Nenhuma alteração foi executada."
        return 1
    fi

    log_info "Pré-flight concluído: todos os VMIDs configurados estão livres."
}

# Consulta um VMID no inventário global. Retornos: 0=encontrado, 1=ausente, 2=erro.
cluster_vmid_exists() {
    local vmid="$1"
    local cluster_resources

    if ! cluster_resources=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null); then
        return 2
    fi

    local parser_rc=0
    perl -MJSON::PP -e '
        my $target = shift;
        local $/;
        my $payload = <STDIN>;
        my $resources = eval { decode_json($payload) };
        exit 2 if $@ || ref($resources) ne "ARRAY";
        for my $resource (@{$resources}) {
            next if ref($resource) ne "HASH" || !defined($resource->{vmid});
            exit 0 if "$resource->{vmid}" eq "$target";
        }
        exit 1;
    ' "$vmid" <<< "$cluster_resources" || parser_rc=$?

    return "$parser_rc"
}

# Verifica se um VMID está livre no cluster. Retornos: 0=livre, 1=ocupado, 2=erro.
check_vmid_available() {
    local vmid="$1"
    local lookup_rc=0

    cluster_vmid_exists "$vmid" || lookup_rc=$?
    case "$lookup_rc" in
        0)
            log_warn "VMID ${vmid} já está em uso no cluster."
            return 1
            ;;
        1)
            log_debug "VMID ${vmid} está disponível."
            return 0
            ;;
        *)
            log_error "Inventário de VMIDs do cluster indisponível ou inválido."
            return 2
            ;;
    esac
}

# =============================================================================
# FUNÇÕES DE IMPORTAÇÃO DE DISCO (compatível PVE 8/9)
# =============================================================================

# Importa um disco de cloud image para uma VM.
# Usa o comando qm importdisk (compatível com PVE 8.x e 9.x em todos os
# tipos de storage, incluindo RBD/Ceph, LVM, ZFS, NFS, etc.).
# Após a importação, anexa o disco ao barramento especificado com discard=on.
import_disk_image() {
    local vmid="$1"
    local image_path="$2"
    local storage="$3"
    local disk_bus="${4:-scsi0}"

    log_info "[VMID:${vmid}] Importando disco de '$(basename "$image_path")' para storage '${storage}'..."

    # Validar que o arquivo de imagem existe e não está vazio
    if [[ ! -f "$image_path" ]]; then
        log_error "[VMID:${vmid}] Arquivo de imagem não encontrado: ${image_path}"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$image_path" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1048576 ]]; then
        log_error "[VMID:${vmid}] Arquivo de imagem muito pequeno (${file_size} bytes). Download pode ter falhado."
        return 1
    fi
    log_debug "[VMID:${vmid}] Imagem validada: $(basename "$image_path") (${file_size} bytes)"

    # Passo 1: Importar o disco usando qm importdisk
    # Este método é universal e funciona em todos os tipos de storage.
    # O output do qm importdisk (barra de progresso) é redirecionado para stderr
    # para não poluir stdout caso esta função seja chamada via $().
    local import_output
    log_info "[VMID:${vmid}] Executando: qm importdisk ${vmid} $(basename "$image_path") ${storage}"
    if ! import_output=$(qm importdisk "$vmid" "$image_path" "$storage" 2>&1); then
        log_error "[VMID:${vmid}] Falha ao importar disco via qm importdisk."
        log_error "[VMID:${vmid}] Output: ${import_output}"
        return 1
    fi
    # Mostrar output da importação no log (via stderr)
    echo "$import_output" >&2

    # Passo 2: Anexar o disco importado ao barramento da VM.
    # Após o importdisk, o Proxmox registra o volume como unused0. Ler o volid
    # real evita assumir nomes internos específicos de RBD/LVM/ZFS.
    local imported_volume
    imported_volume=$(qm config "$vmid" 2>/dev/null | sed -n 's/^unused0: \([^,]*\).*/\1/p')
    if [[ -z "$imported_volume" ]]; then
        log_error "[VMID:${vmid}] Disco importado não foi encontrado como unused0."
        return 1
    fi

    log_info "[VMID:${vmid}] Anexando disco ao barramento ${disk_bus} com discard=on..."
    if ! qm set "$vmid" --"${disk_bus}" "${imported_volume},discard=on"; then
        log_error "[VMID:${vmid}] Falha ao anexar disco importado."
        return 1
    fi

    log_info "[VMID:${vmid}] Disco importado e anexado com sucesso."
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
        # wget: -q silencia output padrão, --show-progress mostra barra de progresso
        # A barra de progresso do wget vai para stderr por padrão.
        # NÃO usar 2>&1 aqui, pois isso redirecionaria a barra de progresso
        # para stdout, poluindo a captura via $() no chamador.
        if wget -q --show-progress --progress=bar:force -O "$dest_path" "$url"; then
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

# Confirma que o VMID está livre. O script nunca remove VMs/templates existentes.
assert_vmid_available() {
    local vmid="$1"
    local name="$2"
    local check_rc

    check_vmid_available "$vmid" && check_rc=0 || check_rc=$?
    case "$check_rc" in
        0) return 0 ;;
        1)
            log_error "VMID ${vmid} ('${name}') já está em uso no cluster."
            log_error "O script não remove recursos existentes. Selecione outro VMID ou faça a substituição manual em uma mudança separada e autorizada."
            return 1
            ;;
        *)
            log_error "Não foi possível confirmar a disponibilidade do VMID ${vmid}. Abortando sem alterações."
            return 1
            ;;
    esac
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
    printf "  %-25s %s\n" "Windows ISO Storage:" "${WINDOWS_ISO_STORAGE:-local}"
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
    printf "  %-8s %-35s %-10s\n" "${VMID_UBUNTU_2604}" "ubuntu-2604-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_DEBIAN_12}" "debian-12-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_DEBIAN_13}" "debian-13-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_CENTOS_STREAM_9}" "centos-stream9-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ROCKY_8}" "rocky-8-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ROCKY_9}" "rocky-9-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ORACLE_8}" "oracle-8-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_ORACLE_9}" "oracle-9-template" "Linux"
    printf "  %-8s %-35s %-10s\n" "${VMID_WIN_2019}" "win-server-2019-template" "Windows"
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
