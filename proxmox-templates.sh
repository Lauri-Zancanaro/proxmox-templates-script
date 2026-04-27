#!/usr/bin/env bash
# =============================================================================
# proxmox-templates.sh - Script principal para criação de templates Proxmox VE
# =============================================================================
#
# Descrição:
#   Script automatizado para criação de templates de VMs no Proxmox VE com
#   suporte a Cloud-Init (Linux) e Cloudbase-Init (Windows Server).
#
# Compatibilidade: Proxmox VE 8.x e 9.x
#
# Uso:
#   ./proxmox-templates.sh [COMANDO] [OPÇÕES]
#
# Comandos:
#   all                 Cria todos os templates (Linux + Windows)
#   linux               Cria todos os templates Linux
#   windows             Cria todos os templates Windows Server
#   ubuntu-2404         Cria apenas o template Ubuntu 24.04
#   debian-12           Cria apenas o template Debian 12
#   debian-13           Cria apenas o template Debian 13
#   centos-stream9      Cria apenas o template CentOS Stream 9
#   rocky-8             Cria apenas o template Rocky Linux 8
#   rocky-9             Cria apenas o template Rocky Linux 9
#   win-2022            Cria apenas o template Windows Server 2022
#   win-2025            Cria apenas o template Windows Server 2025
#   finalize-windows    Finaliza template Windows pós-instalação manual
#   list                Lista os templates existentes
#   version             Exibe a versão do Proxmox VE e QEMU detectados
#   help                Exibe esta ajuda
#
# Exemplos:
#   ./proxmox-templates.sh all
#   ./proxmox-templates.sh linux
#   ./proxmox-templates.sh ubuntu-2404
#   ./proxmox-templates.sh finalize-windows 9007
#
# Autor: mecloud360
# Repositório: https://github.com/Lauri-Zancanaro/proxmox-templates-script
# Licença: MIT
# =============================================================================

set -euo pipefail

# Versão do script
readonly SCRIPT_VERSION="1.1.3"

# Diretório base do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Carregar configuração e módulos
# =============================================================================

# Carregar configuração
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck source=config.env
    source "${SCRIPT_DIR}/config.env"
else
    echo "[ERRO] Arquivo de configuração não encontrado: ${SCRIPT_DIR}/config.env"
    echo "Copie o arquivo config.env.example para config.env e edite conforme seu ambiente."
    exit 1
fi

# Carregar funções utilitárias
# shellcheck source=scripts/utils.sh
source "${SCRIPT_DIR}/scripts/utils.sh"

# Carregar módulo de templates Linux
# shellcheck source=scripts/linux-templates.sh
source "${SCRIPT_DIR}/scripts/linux-templates.sh"

# Carregar módulo de templates Windows
# shellcheck source=scripts/windows-templates.sh
source "${SCRIPT_DIR}/scripts/windows-templates.sh"

# =============================================================================
# Função de ajuda
# =============================================================================
show_help() {
    echo ""
    echo "Proxmox VE Template Creation Script v${SCRIPT_VERSION}"
    echo "Compatível com Proxmox VE 8.x e 9.x"
    echo ""
    echo "Uso: $(basename "$0") [COMANDO] [OPÇÕES]"
    echo ""
    echo "Comandos disponíveis:"
    echo ""
    printf "  %-25s %s\n" "all" "Cria todos os templates (Linux + Windows)"
    printf "  %-25s %s\n" "linux" "Cria todos os templates Linux"
    printf "  %-25s %s\n" "windows" "Cria todos os templates Windows Server"
    printf "  %-25s %s\n" "" ""
    printf "  %-25s %s\n" "ubuntu-2404" "Cria template Ubuntu 24.04 LTS (VMID: ${VMID_UBUNTU_2404})"
    printf "  %-25s %s\n" "debian-12" "Cria template Debian 12 Bookworm (VMID: ${VMID_DEBIAN_12})"
    printf "  %-25s %s\n" "debian-13" "Cria template Debian 13 Trixie (VMID: ${VMID_DEBIAN_13})"
    printf "  %-25s %s\n" "centos-stream9" "Cria template CentOS Stream 9 (VMID: ${VMID_CENTOS_STREAM_9})"
    printf "  %-25s %s\n" "rocky-8" "Cria template Rocky Linux 8 (VMID: ${VMID_ROCKY_8})"
    printf "  %-25s %s\n" "rocky-9" "Cria template Rocky Linux 9 (VMID: ${VMID_ROCKY_9})"
    printf "  %-25s %s\n" "win-2022" "Cria template Windows Server 2022 (VMID: ${VMID_WIN_2022})"
    printf "  %-25s %s\n" "win-2025" "Cria template Windows Server 2025 (VMID: ${VMID_WIN_2025})"
    printf "  %-25s %s\n" "" ""
    printf "  %-25s %s\n" "finalize-windows <VMID>" "Finaliza template Windows após instalação"
    printf "  %-25s %s\n" "list" "Lista templates existentes no cluster"
    printf "  %-25s %s\n" "version" "Exibe versão do PVE e QEMU detectados"
    printf "  %-25s %s\n" "help" "Exibe esta mensagem de ajuda"
    echo ""
    echo "Configuração: Edite o arquivo config.env antes de executar."
    echo ""
}

# =============================================================================
# Função: Listar templates existentes
# =============================================================================
list_templates() {
    log_info "Listando templates existentes no cluster Proxmox..."
    echo ""
    printf "  %-8s %-35s %-10s %-15s\n" "VMID" "NOME" "STATUS" "STORAGE"
    printf "  %-8s %-35s %-10s %-15s\n" "--------" "-----------------------------------" "----------" "---------------"

    # Iterar sobre todos os VMIDs de template configurados
    local vmids=(
        "$VMID_UBUNTU_2404"
        "$VMID_DEBIAN_12"
        "$VMID_DEBIAN_13"
        "$VMID_CENTOS_STREAM_9"
        "$VMID_ROCKY_8"
        "$VMID_ROCKY_9"
        "$VMID_WIN_2022"
        "$VMID_WIN_2025"
    )

    for vmid in "${vmids[@]}"; do
        if qm status "$vmid" &>/dev/null; then
            local name status is_template
            name=$(qm config "$vmid" 2>/dev/null | grep "^name:" | awk '{print $2}')
            status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')

            is_template="VM"
            if qm config "$vmid" 2>/dev/null | grep -q "^template: 1"; then
                is_template="Template"
            fi

            printf "  %-8s %-35s %-10s %-15s\n" "$vmid" "${name:-N/A}" "${status} (${is_template})" "$STORAGE_POOL"
        else
            printf "  %-8s %-35s %-10s %-15s\n" "$vmid" "(não criado)" "-" "-"
        fi
    done

    echo ""
}

# =============================================================================
# Função: Exibir versão detectada
# =============================================================================
show_version() {
    detect_pve_version
    echo ""
    echo "Proxmox VE Template Script v${SCRIPT_VERSION}"
    echo ""
    printf "  %-25s %s\n" "Proxmox VE:" "${PVE_FULL_VERSION:-Não detectado}"
    printf "  %-25s %s\n" "PVE Major:" "${PVE_MAJOR_VERSION:-N/A}"
    printf "  %-25s %s\n" "QEMU:" "${QEMU_FULL_VERSION:-Não detectado}"
    printf "  %-25s %s\n" "Método de importação:" "qm importdisk (universal PVE 8.x/9.x)"
    echo ""
}

# =============================================================================
# Validações iniciais
# =============================================================================
run_preflight_checks() {
    check_root
    check_proxmox
    detect_pve_version
    check_dependencies
    check_storage "$STORAGE_POOL"

    # Criar diretório de download se não existir
    mkdir -p "$DOWNLOAD_DIR"

    # Criar diretório de log se necessário
    if [[ -n "${LOG_FILE:-}" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
    fi
}

# =============================================================================
# MAIN - Ponto de entrada
# =============================================================================
main() {
    local command="${1:-help}"
    shift || true

    # Exibir banner
    show_banner

    # Processar comando
    case "$command" in
        all)
            run_preflight_checks
            show_config_summary
            show_template_table

            log_info "Iniciando criação de TODOS os templates..."
            echo ""

            create_all_linux_templates
            create_all_windows_templates

            # Resultado final
            local all_created=()
            all_created+=("${CREATED_LINUX_TEMPLATES[@]}")
            all_created+=("${CREATED_WINDOWS_TEMPLATES[@]}")
            show_results "${all_created[@]}"
            ;;

        linux)
            run_preflight_checks
            show_config_summary
            create_all_linux_templates
            show_results "${CREATED_LINUX_TEMPLATES[@]}"
            ;;

        windows)
            run_preflight_checks
            show_config_summary
            create_all_windows_templates
            ;;

        ubuntu-2404)
            run_preflight_checks
            show_config_summary
            create_ubuntu_2404_template
            ;;

        debian-12)
            run_preflight_checks
            show_config_summary
            create_debian_12_template
            ;;

        debian-13)
            run_preflight_checks
            show_config_summary
            create_debian_13_template
            ;;

        centos-stream9)
            run_preflight_checks
            show_config_summary
            create_centos_stream9_template
            ;;

        rocky-8)
            run_preflight_checks
            show_config_summary
            create_rocky_8_template
            ;;

        rocky-9)
            run_preflight_checks
            show_config_summary
            create_rocky_9_template
            ;;

        win-2022)
            run_preflight_checks
            show_config_summary
            create_win_2022_template
            ;;

        win-2025)
            run_preflight_checks
            show_config_summary
            create_win_2025_template
            ;;

        finalize-windows)
            run_preflight_checks
            finalize_windows_template "$@"
            ;;

        list)
            run_preflight_checks
            list_templates
            ;;

        version|--version|-v)
            show_version
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            log_error "Comando desconhecido: ${command}"
            show_help
            exit 1
            ;;
    esac
}

# Executar
main "$@"
