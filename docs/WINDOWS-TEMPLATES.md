# Guia Completo: Criação de Templates Windows Server no Proxmox VE

A criação de templates Windows Server no Proxmox VE difere significativamente do processo utilizado para distribuições Linux. Enquanto distribuições Linux oferecem *cloud images* prontas e suportam nativamente o Cloud-Init, a Microsoft não disponibiliza imagens pré-configuradas, exigindo o uso do **Cloudbase-Init** [1]. 

Este guia detalha o processo semi-automatizado implementado nos scripts deste repositório, garantindo que suas instâncias Windows Server 2019, 2022 e 2025 sejam provisionadas com hardware otimizado, drivers VirtIO e configurações consistentes [2].

---

## 1. Arquitetura do Processo

O fluxo de criação é dividido em duas fases principais:

| Fase | Automação | Descrição |
|---|---|---|
| **Fase 1: Preparação e Instalação** | 100% Automatizada | O script valida dependências, baixa drivers VirtIO, gera um ISO com `autounattend.xml`, cria a VM com hardware otimizado e anexa os ISOs necessários. |
| **Fase 2: Configuração e Sysprep** | Manual | O administrador acessa a VM, instala o Cloudbase-Init, executa o Sysprep e, após o desligamento, utiliza o script para converter a VM em template [3]. |

---

## 2. Pré-requisitos

Antes de iniciar, certifique-se de que os seguintes itens estão disponíveis no seu ambiente Proxmox:

1. **ISO do Windows Server:**
   * Faça o download da versão de avaliação (2019, 2022 ou 2025) diretamente do [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/).
   * Faça o upload do arquivo para o diretório de ISOs do Proxmox (geralmente `/var/lib/vz/template/iso/`).
   * **Importante:** O nome do arquivo deve conter o ano da versão (ex.: `windows-server-2019-eval.iso`, `windows-server-2022-eval.iso` ou `win-2025.iso`).

2. **Configuração local:**
   * Crie o arquivo local com `cp config.local.env.example config.local.env` e proteja-o com `chmod 600 config.local.env`.
   * Configure `WINDOWS_ISO_STORAGE` com o storage que publica as ISOs como `<storage>:iso/<arquivo>`; ele deve corresponder ao diretório `DOWNLOAD_DIR` do nó.
   * Revise `WIN_ADMIN_USER` e `WIN_ADMIN_PASSWORD` somente em `config.local.env`. Essas credenciais serão injetadas durante a instalação automática e não devem ser commitadas [4].

---

## 3. Passo a Passo: Fase 1 (Automatizada)

Execute o script principal passando o parâmetro correspondente à versão desejada:

```bash
# Para Windows Server 2019
./proxmox-templates.sh win-2019

# Para Windows Server 2022
./proxmox-templates.sh win-2022

# Para Windows Server 2025
./proxmox-templates.sh win-2025
```

> **Segurança:** o ISO `autounattend` contém a senha temporária em texto claro durante a instalação. Restrinja o acesso root/backup ao nó, use uma senha exclusiva e finalize o template assim que concluir Cloudbase-Init e Sysprep; o comando `finalize-windows` remove esse ISO.

### O que o script faz nos bastidores?
1. **Verificação:** Confirma o storage configurado, a existência da ISO do Windows e baixa automaticamente a ISO de drivers VirtIO mais recente [2].
2. **Geração do `autounattend.xml`:** Cria um arquivo de resposta XML e um ISO temporário que contém somente o driver boot-critical `vioscsi` na pasta oficial `$WinPEDriver$`. O Windows Setup procura essa pasta automaticamente nas mídias montadas, sem depender de uma letra fixa. Rede, balloon e os demais componentes são instalados pelo VirtIO Guest Tools no primeiro logon; o instalador é localizado dinamicamente entre os volumes disponíveis [4].
3. **Criação da VM:** Provisiona uma nova VM com hardware recomendado para Windows:
   * **Machine Type:** `q35`
   * **BIOS:** OVMF (UEFI) com Secure Boot
   * **TPM:** v2.0
   * **SCSI Controller:** `virtio-scsi-single`
   * **Disco:** VirtIO Block com `discard=on` (Thin Provisioning)
   * **Tipo de SO:** `win10` para Windows Server 2019; `win11` para 2022/2025
   * **Drivers VirtIO:** diretórios `2k19`, `2k22` ou `2k25`, conforme a versão
   * **Particionamento UEFI/GPT:** EFI, MSR e Windows; somente EFI e Windows são modificadas no `autounattend`, conforme o esquema oficial da Microsoft.
4. **Anexação de ISOs:** Anexa Windows em `ide0`, VirtIO em `ide1` e `autounattend` em `ide2`, usando o storage configurado. O fluxo não presume que essas mídias serão `D:`, `E:` ou `F:` dentro do Windows PE.

---

## 4. Passo a Passo: Fase 2 (Manual)

Após o script finalizar a Fase 1, a VM estará criada e pronta para ser iniciada.

### 4.1. Instalação do Windows
1. Inicie a VM recém-criada através da interface web do Proxmox ou via CLI (`qm start <VMID>`).
2. Abra o console da VM pelo **noVNC** integrado à interface web do Proxmox.
3. **Não é necessário interagir.** A instalação ocorrerá de forma 100% autônoma graças ao arquivo `autounattend.xml`. O Windows será instalado, reiniciará e fará o primeiro logon automaticamente.
4. Após o primeiro logon, um script PowerShell localiza o instalador VirtIO entre as mídias disponíveis e o executa com `/install /quiet /norestart`. Confirme `qm agent <VMID> ping` antes de considerar a etapa concluída; se o agente não responder, execute o instalador VirtIO Guest Tools pelo console e confirme a instalação. As opções `/S /v"/qn"` não se aplicam a esse instalador.

### 4.2. Configuração do Sistema e Aplicações
Este é o momento ideal para aplicar configurações que você deseja que todos os clones herdem:
* Instalar atualizações do Windows Update.
* Configurar regras de Firewall.
* Instalar softwares padrão (ex: agentes de monitoramento, navegadores, ferramentas de backup) [3].
* **Nota:** Não ingresse a máquina em um domínio Active Directory neste momento.

### 4.3. Instalação e Configuração do Cloudbase-Init
O Cloudbase-Init é o equivalente Windows do Cloud-Init. Ele permite que o Proxmox injete configurações (IP, hostname, senhas) quando um clone for inicializado [1].

1. Faça o download do instalador x64 estável no site oficial: [Cloudbase-Init Download](https://www.cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi). Se o convidado não tiver acesso à Internet, copie o MSI para uma ISO no storage de ISO, anexe temporariamente ao convidado e instale a partir da unidade montada. Depois, antes de `finalize-windows`, restaure o ISO `autounattend-<versão>.iso` em `ide2`, pois o comando valida essa mídia como salvaguarda.
2. Execute o instalador. Durante o assistente:
   * Escolha o usuário `Administrator` (ou altere o `username` nos arquivos principal e `cloudbase-init-unattend.conf` se usar instalação silenciosa, cujo default é `Admin`).
   * Selecione a porta serial `COM1` para logging e diagnóstico (o script já adicionou esta porta à VM). Os metadados do Proxmox são lidos pelo drive Cloud-Init/ConfigDrive, não pela porta serial.
   * **ATENÇÃO:** Na última tela do instalador, **DESMARQUE** as opções "Run Sysprep" e "Reboot". Clique em Finish.
3. Ajuste **ambos** os arquivos em `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\`: `cloudbase-init.conf` (execução regular nos clones) e `cloudbase-init-unattend.conf` (passo de Sysprep). Use os exemplos sem credenciais testados na VM 9012: [`examples/windows/cloudbase-init.conf`](../examples/windows/cloudbase-init.conf) e [`examples/windows/cloudbase-init-unattend.conf`](../examples/windows/cloudbase-init-unattend.conf). Restrinja o provedor de metadados a `ConfigDriveService` e verifique que `username=Administrator` está presente nos dois arquivos. A configuração principal segue o padrão:

```ini
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\
verbose=true
debug=true
log_dir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
log_file=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=COM1,115200,N,8
mtu_use_dhcp_config=false
ntp_use_dhcp_config=false
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
check_latest_version=false
allow_reboot=true
plugins=cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin
```

O arquivo `cloudbase-init-unattend.conf` usa apenas os plugins necessários ao passo de especialização (MTU, hostname e extensão de volumes), com `allow_reboot=false` e `stop_service_on_exit=false`. O instalador 1.1.8 usa `log_dir`/`log_file`, não `logdir`/`logfile`. Confira a importação dos plugins e o serviço `cloudbase-init` configurado como `AUTO_START` antes do Sysprep.

### 4.4. Execução do Sysprep
O Sysprep (System Preparation Tool) remove identificadores únicos (como o SID) da instalação, garantindo que cada clone gerado a partir do template seja tratado como uma máquina única na rede [3].

1. Abra o Prompt de Comando (CMD) como Administrador.
2. Navegue até o diretório de configuração do Cloudbase-Init:
   ```cmd
   cd "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf"
   ```
3. Execute o Sysprep utilizando o arquivo de resposta fornecido pelo próprio Cloudbase-Init:
   ```cmd
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:Unattend.xml
   ```
4. Aguarde. O Windows executará a rotina de limpeza e **desligará a VM automaticamente**.

---

## 5. Finalização do Template

Com a VM desligada após o Sysprep, retorne ao shell do servidor Proxmox e execute o comando de finalização, informando o VMID da máquina:

```bash
./proxmox-templates.sh finalize-windows <VMID>
```

**Exemplo:**
```bash
./proxmox-templates.sh finalize-windows 9012  # Windows Server 2019
./proxmox-templates.sh finalize-windows 9007
```

### O que o script de finalização faz?
1. Verifica se a VM está desligada.
2. Remove as três unidades de CD-ROM virtuais (ISOs de instalação).
3. Adiciona um novo drive Cloud-Init configurado para utilizar o storage pool definido no `config.env`.
4. Altera a ordem de boot para iniciar diretamente pelo disco SCSI (`scsi0`).
5. Converte a VM definitivamente em um Template [1].
6. Remove o ISO `autounattend` do mesmo storage configurado e os arquivos temporários que continham a senha em texto claro.

---

## 6. Provisionando Clones Windows

Seu template Windows Server está pronto! Para criar uma nova VM a partir dele:

1. Na interface do Proxmox, clique com o botão direito no template e selecione **Clone**.
2. Escolha **Linked Clone** (mais rápido e economiza espaço) ou **Full Clone**.
3. Na nova VM, acesse a aba **Cloud-Init**.
4. Configure as opções desejadas:
   * **User:** `Administrator`
   * **Password:** Defina a senha do administrador para esta instância específica.
   * **IP Config:** Defina IP estático ou DHCP.
5. Clique em **Regenerate Image**.
6. Inicie a VM. O Cloudbase-Init lerá o drive virtual gerado pelo Proxmox e aplicará as configurações de rede, senha e hostname durante a inicialização [1].

---

## Referências

[1] Proxmox Wiki: "Cloud-Init Support". Disponível em: https://pve.proxmox.com/wiki/Cloud-Init_Support
[2] Proxmox Wiki: "Windows VirtIO Drivers". Disponível em: https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers
[3] ARPHost: "How to Create a Windows Server 2025 Cloud-Init Template in Proxmox". Disponível em: https://arphost.com/how-to-create-a-windows-server-2025-cloud-init-template-in-proxmox/
[4] Proxmox Forum: "[TUTORIAL] - windows cloud init working". Disponível em: https://forum.proxmox.com/threads/windows-cloud-init-working.83511/
[5] Proxmox Wiki: "Windows 2019 guest best practices". Disponível em: https://pve.proxmox.com/wiki/Windows_2019_guest_best_practices
[6] Proxmox Forum: "Proxmox Packer templates for Windows Server 2019/2022/2025". Disponível em: https://forum.proxmox.com/threads/proxmox-packer-templates-for-windows-server-2019-2022-2025-%E2%80%94-cloudbase-init-ansible-openssh-repo-overview.185227/
