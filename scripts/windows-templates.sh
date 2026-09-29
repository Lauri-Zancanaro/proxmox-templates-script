#!/usr/bin/env bash
# =============================================================================
# windows-templates.sh - Criação de templates Windows Server com Cloudbase-Init
# =============================================================================
# Este script contém as funções para criação de templates Windows Server no
# Proxmox VE com suporte a Cloudbase-Init para automação de deploy.
#
# Compatibilidade: Proxmox VE 8.x e 9.x
#
# Versões suportadas:
#   - Windows Server 2022 (Evaluation)
#   - Windows Server 2025 (Evaluation)
#
# IMPORTANTE: A criação de templates Windows é um processo semi-automatizado.
# Diferente do Linux, não existem cloud images prontas para Windows.
# O processo requer:
#   1. Download manual da ISO do Windows Server (Microsoft Evaluation Center)
#   2. Download automático dos drivers VirtIO
#   3. Geração do ISO de autounattend para instalação desatendida
#   4. Criação da VM, instalação automática e conversão em template
#
# Referências:
#   - https://pve.proxmox.com/wiki/Cloud-Init_Support#_cloud_init_on_windows
#   - https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers
#   - https://cloudbase.it/cloudbase-init/
#   - https://computingforgeeks.com/windows-server-2022-template-proxmox/
# =============================================================================

# Variável global para armazenar o caminho da ISO do Windows encontrada
WIN_ISO_PATH=""
VIRTIO_ISO_PATH=""

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

# =============================================================================
# FUNÇÃO: Verificar pré-requisitos para templates Windows
# =============================================================================
check_windows_prerequisites() {
    local win_version="$1"  # "2022" ou "2025"

    # Verificar dependências
    if ! check_windows_dependencies; then
        return 1
    fi

    # Verificar se a ISO do Windows existe no diretório de ISOs
    local iso_dir="/var/lib/vz/template/iso"
    local iso_found=false

    # Buscar ISO com padrões flexíveis (case-insensitive via shopt)
    local iso_file
    for iso_file in "${iso_dir}"/*"${win_version}"*.iso; do
        if [[ -f "$iso_file" ]]; then
            iso_found=true
            WIN_ISO_PATH="$iso_file"
            log_info "ISO do Windows Server ${win_version} encontrada: ${iso_file}"
            break
        fi
    done

    if [[ "$iso_found" == "false" ]]; then
        log_error "ISO do Windows Server ${win_version} NÃO encontrada em ${iso_dir}."
        log_error ""
        log_error "Para criar o template Windows Server ${win_version}, você precisa:"
        log_error "  1. Baixar a ISO de avaliação do Microsoft Evaluation Center:"
        if [[ "$win_version" == "2022" ]]; then
            log_error "     https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022"
        else
            log_error "     https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025"
        fi
        log_error "  2. Copiar a ISO para: ${iso_dir}/"
        log_error "  3. O nome do arquivo deve conter '${win_version}'"
        log_error "     Exemplo: windows-server-${win_version}-eval.iso"
        log_error ""
        return 1
    fi

    # Verificar/baixar VirtIO drivers ISO
    local virtio_iso="${iso_dir}/virtio-win.iso"
    if [[ ! -f "$virtio_iso" ]]; then
        log_info "Baixando ISO dos drivers VirtIO..."
        if ! wget -q --show-progress -O "$virtio_iso" "$URL_VIRTIO_ISO"; then
            log_error "Falha ao baixar drivers VirtIO."
            return 1
        fi
        log_info "Drivers VirtIO baixados com sucesso."
    else
        log_info "ISO dos drivers VirtIO já existe: ${virtio_iso}"
    fi

    VIRTIO_ISO_PATH="$virtio_iso"
    return 0
}

# =============================================================================
# FUNÇÃO: Gerar arquivo autounattend.xml
# =============================================================================
# Argumentos:
#   $1 - Versão do Windows ("2022" ou "2025")
#   $2 - Caminho de saída para o arquivo XML
# =============================================================================
generate_autounattend_xml() {
    local win_version="$1"
    local output_path="$2"

    # Definir o path dos drivers VirtIO conforme a versão
    local virtio_driver_path
    if [[ "$win_version" == "2022" ]]; then
        virtio_driver_path="2k22"
    else
        virtio_driver_path="2k25"
    fi

    local win_admin_user_xml win_admin_password_xml previous_umask
    win_admin_user_xml=$(xml_escape "$WIN_ADMIN_USER")
    win_admin_password_xml=$(xml_escape "$WIN_ADMIN_PASSWORD")
    previous_umask=$(umask)
    umask 077

    log_info "Gerando autounattend.xml para Windows Server ${win_version}..."

    if ! cat > "$output_path" << XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

  <!-- ================================================================== -->
  <!-- PASS 1: windowsPE - Configuração durante o boot do instalador      -->
  <!-- ================================================================== -->
  <settings pass="windowsPE">

    <!-- Configuração Internacional -->
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <!-- Drivers VirtIO para reconhecimento do disco durante instalação -->
    <component name="Microsoft-Windows-PnpCustomizationsWinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <DriverPaths>
        <PathAndCredentials wcm:action="add" wcm:keyValue="1">
          <Path>E:\\vioscsi\\${virtio_driver_path}\\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="2">
          <Path>E:\\NetKVM\\${virtio_driver_path}\\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="3">
          <Path>E:\\Balloon\\${virtio_driver_path}\\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="4">
          <Path>E:\\viostor\\${virtio_driver_path}\\amd64</Path>
        </PathAndCredentials>
      </DriverPaths>
    </component>

    <!-- Configuração do Setup (disco, partições, imagem) -->
    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">

      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <!-- Partição EFI System -->
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Size>260</Size>
              <Type>EFI</Type>
            </CreatePartition>
            <!-- Partição MSR -->
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Size>128</Size>
              <Type>MSR</Type>
            </CreatePartition>
            <!-- Partição Windows -->
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Extend>true</Extend>
              <Type>Primary</Type>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>FAT32</Format>
              <Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order>
              <PartitionID>3</PartitionID>
              <Format>NTFS</Format>
              <Label>Windows</Label>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>2</Value>
            </MetaData>
          </InstallFrom>
        </OSImage>
      </ImageInstall>

      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>

  <!-- ================================================================== -->
  <!-- PASS 4: specialize - Configurações pós-instalação                  -->
  <!-- ================================================================== -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <ComputerName>*</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>

    <!-- Habilitar Remote Desktop -->
    <component name="Microsoft-Windows-TerminalServices-LocalSessionManager"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <fDenyTSConnections>false</fDenyTSConnections>
    </component>

    <!-- Firewall: permitir Remote Desktop -->
    <component name="Networking-MPSSVC-Svc"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <FirewallGroups>
        <FirewallGroup wcm:action="add" wcm:keyValue="RemoteDesktop">
          <Active>true</Active>
          <Group>Remote Desktop</Group>
          <Profile>all</Profile>
        </FirewallGroup>
      </FirewallGroups>
    </component>
  </settings>

  <!-- ================================================================== -->
  <!-- PASS 7: oobeSystem - Configuração OOBE                             -->
  <!-- ================================================================== -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <UserAccounts>
        <AdministratorPassword>
          <Value>${win_admin_password_xml}</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>${win_admin_user_xml}</Username>
        <Password>
          <Value>${win_admin_password_xml}</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>1</LogonCount>
      </AutoLogon>

      <!-- Script de primeira inicialização: instala VirtIO Guest Agent -->
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -Command "Set-ExecutionPolicy Bypass -Scope Process -Force"</CommandLine>
          <Description>Set execution policy</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>E:\virtio-win-guest-tools.exe /S /v"/qn ADDLOCAL=ALL"</CommandLine>
          <Description>Install VirtIO Guest Tools and QEMU Guest Agent</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>powershell.exe -Command "Start-Sleep -Seconds 30"</CommandLine>
          <Description>Wait for VirtIO installation</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>

    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
  </settings>
</unattend>
XMLEOF
    then
        umask "$previous_umask"
        log_error "Falha ao gravar o arquivo autounattend.xml."
        return 1
    fi

    if ! chmod 0600 "$output_path"; then
        umask "$previous_umask"
        log_error "Falha ao proteger as permissões do arquivo autounattend.xml."
        return 1
    fi
    umask "$previous_umask"

    log_info "Arquivo autounattend.xml gerado: ${output_path}"
    return 0
}

# =============================================================================
# FUNÇÃO: Gerar ISO do autounattend
# =============================================================================
generate_autounattend_iso() {
    local xml_path="$1"
    local iso_output="$2"

    local tmp_dir previous_umask
    previous_umask=$(umask)
    umask 077
    if ! tmp_dir=$(mktemp -d); then
        umask "$previous_umask"
        log_error "Falha ao criar diretório temporário para o autounattend."
        return 1
    fi

    if ! cp "$xml_path" "${tmp_dir}/autounattend.xml"; then
        rm -rf "$tmp_dir"
        umask "$previous_umask"
        log_error "Falha ao preparar o autounattend.xml para geração do ISO."
        return 1
    fi

    log_info "Gerando ISO do autounattend..."
    if ! genisoimage -o "$iso_output" -J -r "$tmp_dir" 2>/dev/null; then
        log_error "Falha ao gerar ISO do autounattend."
        rm -rf "$tmp_dir"
        umask "$previous_umask"
        return 1
    fi

    rm -rf "$tmp_dir"
    if ! chmod 0600 "$iso_output"; then
        rm -f "$iso_output"
        umask "$previous_umask"
        log_error "Falha ao proteger as permissões do ISO autounattend."
        return 1
    fi
    umask "$previous_umask"
    log_info "ISO do autounattend gerado: ${iso_output}"
    return 0
}

# =============================================================================
# FUNÇÃO PRINCIPAL: Criar template Windows Server
# =============================================================================
# Argumentos:
#   $1 - VMID do template
#   $2 - Nome do template
#   $3 - Versão do Windows ("2022" ou "2025")
#   $4 - Descrição do template
# =============================================================================
create_windows_template() (
    local vmid="$1"
    local name="$2"
    local win_version="$3"
    local description="${4:-Windows Server ${win_version} Template}"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Iniciando criação do template: ${name} (VMID: ${vmid})"
    log_info "Proxmox VE: ${PVE_FULL_VERSION:-N/A} | QEMU: ${QEMU_FULL_VERSION:-N/A}"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # -------------------------------------------------------------------------
    # Passo 1: Verificar pré-requisitos
    # -------------------------------------------------------------------------
    if ! check_windows_prerequisites "$win_version"; then
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 2: Verificar e preparar VMID
    # -------------------------------------------------------------------------
    if ! assert_vmid_available "$vmid" "$name"; then
        log_error "Não foi possível preparar o VMID ${vmid}. Pulando '${name}'."
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 3: Gerar autounattend.xml e ISO
    # -------------------------------------------------------------------------
    local unattend_dir="/tmp/proxmox-win-unattend-${win_version}"
    local previous_umask
    previous_umask=$(umask)
    umask 077
    rm -rf "$unattend_dir"
    mkdir -p "$unattend_dir"
    umask "$previous_umask"

    local xml_path="${unattend_dir}/autounattend.xml"
    local autounattend_iso="/var/lib/vz/template/iso/autounattend-${win_version}.iso"
    local preserve_autounattend_iso=false
    trap 'rm -rf "$unattend_dir"; if [[ "$preserve_autounattend_iso" != "true" ]]; then rm -f "$autounattend_iso"; fi' EXIT

    if ! generate_autounattend_xml "$win_version" "$xml_path"; then
        rm -rf "$unattend_dir"
        return 1
    fi

    if ! generate_autounattend_iso "$xml_path" "$autounattend_iso"; then
        rm -rf "$unattend_dir"
        rm -f "$autounattend_iso"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 4: Criar a VM com hardware otimizado para Windows
    # -------------------------------------------------------------------------
    log_info "[${name}] Criando VM base com hardware otimizado para Windows..."

    # Determinar o ostype adequado para a versão do Windows
    # PVE 8/9: win11 é o tipo mais recente disponível para Windows Server 2022/2025
    local win_ostype="win11"

    # Montar argumentos de criação da VM
    local create_args=(
        "$vmid"
        --name "$name"
        --ostype "$win_ostype"
        --machine q35
        --bios ovmf
        --efidisk0 "${STORAGE_POOL}:1,efitype=4m,pre-enrolled-keys=1"
        --tpmstate0 "${STORAGE_POOL}:1,version=v2.0"
        --cpu host
        --cores "$WIN_CORES"
        --memory "$WIN_MEMORY"
        --scsihw virtio-scsi-single
        --scsi0 "${STORAGE_POOL}:${WIN_DISK_SIZE},iothread=1,discard=on"
        --net0 "virtio,bridge=${BRIDGE_NET}"
        --serial0 socket
        --serial1 socket
        --description "$description"
        --tags "template,cloudbase-init,windows,pve${PVE_MAJOR_VERSION:-8}"
    )

    if ! qm create "${create_args[@]}"; then
        log_error "[${name}] Falha ao criar a VM base."
        rm -rf "$unattend_dir"
        rm -f "$autounattend_iso"
        return 1
    fi

    # -------------------------------------------------------------------------
    # Passo 5: Anexar ISOs (Windows, autounattend, VirtIO)
    # -------------------------------------------------------------------------
    log_info "[${name}] Anexando ISOs de instalação..."

    local win_iso_filename
    win_iso_filename=$(basename "$WIN_ISO_PATH")
    local virtio_iso_filename
    virtio_iso_filename=$(basename "$VIRTIO_ISO_PATH")

    if ! qm set "$vmid" --ide0 "local:iso/${win_iso_filename},media=cdrom" || \
       ! qm set "$vmid" --ide1 "local:iso/autounattend-${win_version}.iso,media=cdrom" || \
       ! qm set "$vmid" --ide2 "local:iso/${virtio_iso_filename},media=cdrom"; then
        log_error "[${name}] Falha ao anexar as ISOs de instalação."
        qm destroy "$vmid" --purge 2>/dev/null || true
        rm -rf "$unattend_dir"
        rm -f "$autounattend_iso"
        return 1
    fi

    # O XML em texto claro não é mais necessário depois que o ISO foi gerado.
    rm -rf "$unattend_dir"

    # Configurar boot para CD-ROM primeiro
    if ! qm set "$vmid" --boot "order=ide0;scsi0" || \
       ! qm set "$vmid" --vga std || \
       ! qm set "$vmid" --agent enabled=1; then
        log_error "[${name}] Falha ao concluir a configuração de hardware Windows."
        qm destroy "$vmid" --purge 2>/dev/null || true
        rm -f "$autounattend_iso"
        return 1
    fi
    preserve_autounattend_iso=true

    # Configurar display (VNC - compatível com noVNC do Proxmox Web UI)
    # QEMU Guest Agent habilitado no bloco anterior.

    # -------------------------------------------------------------------------
    # Passo 6: Informar próximos passos manuais
    # -------------------------------------------------------------------------
    log_info ""
    log_info "╔══════════════════════════════════════════════════════════════════╗"
    log_info "║  VM ${vmid} (${name}) criada e pronta para instalação.         ║"
    log_info "╚══════════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "PRÓXIMOS PASSOS (semi-automatizado):"
    log_info ""
    log_info "  1. Iniciar a VM:"
    log_info "     qm start ${vmid}"
    log_info ""
    log_info "  2. Acessar o console via noVNC no Proxmox Web UI"
    log_info "     e aguardar a instalação automática do Windows."
    log_info ""
    log_info "  3. Após a instalação e primeiro login automático:"
    log_info "     - O VirtIO Guest Tools será instalado automaticamente."
    log_info "     - Instale o Cloudbase-Init manualmente:"
    log_info "       Download: https://cloudbase.it/cloudbase-init/#download"
    log_info "     - Configure o Cloudbase-Init (cloudbase-init.conf):"
    log_info "       [DEFAULT]"
    log_info "       username=Administrator"
    log_info "       groups=Administrators"
    log_info "       inject_user_password=true"
    log_info "       first_logon_behaviour=no"
    log_info "       metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService"
    log_info ""
    log_info "  4. Execute o Sysprep (Generalize + OOBE + Shutdown):"
    log_info "     C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown"
    log_info ""
    log_info "  5. Após o shutdown, finalize o template:"
    log_info "     ./proxmox-templates.sh finalize-windows ${vmid}"
    log_info ""

    return 0
)

# =============================================================================
# FUNÇÃO: Finalizar template Windows (pós-instalação manual)
# =============================================================================
finalize_windows_template() {
    local vmid="${1:-}"
    local win_version expected_name

    if [[ -z "$vmid" ]]; then
        log_error "VMID não informado. Uso: finalize-windows <VMID>"
        return 1
    fi

    case "$vmid" in
        "$VMID_WIN_2022")
            win_version="2022"
            expected_name="win-server-2022-template"
            ;;
        "$VMID_WIN_2025")
            win_version="2025"
            expected_name="win-server-2025-template"
            ;;
        *)
            log_error "VMID ${vmid} não corresponde aos templates Windows configurados (${VMID_WIN_2022}/${VMID_WIN_2025})."
            return 1
            ;;
    esac

    local inventory_rc=0
    cluster_vmid_exists "$vmid" || inventory_rc=$?
    case "$inventory_rc" in
        0) ;;
        1)
            log_error "VMID ${vmid} não existe no inventário global do cluster."
            return 1
            ;;
        *)
            log_error "Inventário global do cluster indisponível ou inválido; finalização bloqueada."
            return 1
            ;;
    esac

    # Verificar se a VM pertence ao nó atual e corresponde ao recurso esperado.
    if ! qm status "$vmid" &>/dev/null; then
        log_error "VM ${vmid} não encontrada no nó atual."
        return 1
    fi

    local vm_config
    if ! vm_config=$(qm config "$vmid" 2>/dev/null); then
        log_error "Não foi possível ler a configuração da VM ${vmid}."
        return 1
    fi

    if grep -q '^template: 1$' <<< "$vm_config"; then
        log_error "VM ${vmid} já é um template."
        return 1
    fi
    if ! grep -q "^name: ${expected_name}$" <<< "$vm_config"; then
        log_error "Nome inesperado para VM ${vmid}; esperado '${expected_name}'."
        return 1
    fi
    local vm_tags normalized_tags expected_tags
    vm_tags=$(awk -F': ' '/^tags:/{print $2; exit}' <<< "$vm_config")
    normalized_tags=$(tr ',;' '\n' <<< "$vm_tags" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u | paste -sd';' -)
    expected_tags=$(printf '%s\n' cloudbase-init "pve${PVE_MAJOR_VERSION:-8}" template windows | LC_ALL=C sort | paste -sd';' -)
    if [[ "$normalized_tags" != "$expected_tags" ]]; then
        log_error "VM ${vmid} não contém exatamente as tags esperadas: ${expected_tags}."
        return 1
    fi
    local ide1_config ide1_volume
    ide1_config=$(awk -F': ' '/^ide1:/{print $2; exit}' <<< "$vm_config")
    ide1_volume="${ide1_config%%,*}"
    if [[ "$ide1_volume" != "local:iso/autounattend-${win_version}.iso" ]]; then
        log_error "VM ${vmid} não contém o ISO autounattend esperado para Windows ${win_version}."
        return 1
    fi

    # Verificar se a VM está desligada
    local status
    status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
    if [[ "$status" != "stopped" ]]; then
        log_error "VM ${vmid} precisa estar desligada. Status atual: ${status}"
        log_error "Aguarde o Sysprep finalizar e desligar a VM automaticamente."
        return 1
    fi

    log_info "Finalizando template Windows (VMID: ${vmid})..."

    # Remover ISOs de instalação
    log_info "Removendo ISOs de instalação..."
    if ! qm set "$vmid" --delete ide0 2>/dev/null || \
       ! qm set "$vmid" --delete ide1 2>/dev/null || \
       ! qm set "$vmid" --delete ide2 2>/dev/null; then
        log_error "Falha ao remover uma ou mais ISOs da VM ${vmid}."
        return 1
    fi

    # Adicionar drive Cloud-Init
    log_info "Adicionando drive Cloud-Init..."
    if ! qm set "$vmid" --ide2 "${STORAGE_POOL}:cloudinit"; then
        log_error "Falha ao adicionar o drive Cloud-Init à VM ${vmid}."
        return 1
    fi

    # Configurar boot
    if ! qm set "$vmid" --boot order=scsi0; then
        log_error "Falha ao configurar o boot da VM ${vmid}."
        return 1
    fi

    # Converter para template
    log_info "Convertendo para template..."
    if qm template "$vmid"; then
        # O ISO autounattend contém a senha em texto claro e não é mais necessário.
        rm -f "/var/lib/vz/template/iso/autounattend-${win_version}.iso"
        rm -rf "/tmp/proxmox-win-unattend-${win_version}"
        log_info "Template Windows finalizado com sucesso! (VMID: ${vmid})"
    else
        log_error "Falha ao converter para template."
        return 1
    fi

    return 0
}

# =============================================================================
# FUNÇÕES ESPECÍFICAS POR VERSÃO
# =============================================================================

create_win_2022_template() {
    create_windows_template \
        "$VMID_WIN_2022" \
        "win-server-2022-template" \
        "2022" \
        "Windows Server 2022 - Cloudbase-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

create_win_2025_template() {
    create_windows_template \
        "$VMID_WIN_2025" \
        "win-server-2025-template" \
        "2025" \
        "Windows Server 2025 - Cloudbase-Init Template | PVE ${PVE_FULL_VERSION:-N/A} | Criado em: $(date '+%Y-%m-%d')"
}

# =============================================================================
# FUNÇÃO: Criar todos os templates Windows
# =============================================================================
create_all_windows_templates() {
    local created=()
    local failed=()
    local skipped=()

    log_info "Iniciando criação de templates Windows Server..."
    echo ""

    # Windows Server 2022
    WIN_ISO_PATH=""
    if create_win_2022_template; then
        created+=("win-server-2022-template (VMID: ${VMID_WIN_2022})")
    else
        # Verificar se foi por falta de ISO (skip) ou erro real
        if [[ -z "${WIN_ISO_PATH:-}" ]]; then
            skipped+=("win-server-2022-template (VMID: ${VMID_WIN_2022}) - ISO não encontrada")
        else
            failed+=("win-server-2022-template (VMID: ${VMID_WIN_2022})")
        fi
    fi

    # Windows Server 2025
    WIN_ISO_PATH=""
    if create_win_2025_template; then
        created+=("win-server-2025-template (VMID: ${VMID_WIN_2025})")
    else
        if [[ -z "${WIN_ISO_PATH:-}" ]]; then
            skipped+=("win-server-2025-template (VMID: ${VMID_WIN_2025}) - ISO não encontrada")
        else
            failed+=("win-server-2025-template (VMID: ${VMID_WIN_2025})")
        fi
    fi

    # Resumo
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "RESUMO - Templates Windows"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ ${#created[@]} -gt 0 ]]; then
        log_info "VMs criadas (aguardando instalação): ${#created[@]}"
        for item in "${created[@]}"; do
            log_info "  ✓ ${item}"
        done
    fi

    if [[ ${#skipped[@]} -gt 0 ]]; then
        log_warn "Pulados (ISO não encontrada): ${#skipped[@]}"
        for item in "${skipped[@]}"; do
            log_warn "  ⊘ ${item}"
        done
    fi

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_error "Falhas: ${#failed[@]}"
        for item in "${failed[@]}"; do
            log_error "  ✗ ${item}"
        done
    fi

    echo ""

    # shellcheck disable=SC2034
    CREATED_WINDOWS_TEMPLATES=("${created[@]}")
    # shellcheck disable=SC2034
    FAILED_WINDOWS_TEMPLATES=("${failed[@]}")
    # shellcheck disable=SC2034
    SKIPPED_WINDOWS_TEMPLATES=("${skipped[@]}")
}
