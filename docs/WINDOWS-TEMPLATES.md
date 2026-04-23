# Guia Completo: Criação de Templates Windows Server no Proxmox VE

A criação de templates Windows Server no Proxmox VE difere significativamente do processo utilizado para distribuições Linux. Enquanto distribuições Linux oferecem *cloud images* prontas e suportam nativamente o Cloud-Init, a Microsoft não disponibiliza imagens pré-configuradas, exigindo o uso do **Cloudbase-Init** [1]. 

Este guia detalha o processo semi-automatizado implementado nos scripts deste repositório, garantindo que suas instâncias Windows Server 2022 e 2025 sejam provisionadas com hardware otimizado, drivers VirtIO e configurações consistentes [2].

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
   * Faça o download da versão de avaliação (2022 ou 2025) diretamente do [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/).
   * Faça o upload do arquivo para o diretório de ISOs do Proxmox (geralmente `/var/lib/vz/template/iso/`).
   * **Importante:** O nome do arquivo deve conter o ano da versão (ex: `windows-server-2022-eval.iso` ou `win-2025.iso`).

2. **Configuração do `config.env`:**
   * Revise as variáveis `WIN_ADMIN_USER` e `WIN_ADMIN_PASSWORD` no arquivo `config.env`. Estas credenciais serão injetadas durante a instalação automática [4].

---

## 3. Passo a Passo: Fase 1 (Automatizada)

Execute o script principal passando o parâmetro correspondente à versão desejada:

```bash
# Para Windows Server 2022
./proxmox-templates.sh win-2022

# Para Windows Server 2025
./proxmox-templates.sh win-2025
```

### O que o script faz nos bastidores?
1. **Verificação:** Confirma a existência da ISO do Windows e baixa automaticamente a ISO de drivers VirtIO mais recente [2].
2. **Geração do `autounattend.xml`:** Cria um arquivo de resposta XML e o converte em um arquivo ISO temporário. Este arquivo instrui o instalador do Windows a carregar os drivers VirtIO de armazenamento durante o boot, particionar o disco, aceitar a EULA, definir a senha do administrador e instalar o QEMU Guest Agent no primeiro logon [4].
3. **Criação da VM:** Provisiona uma nova VM com hardware recomendado para Windows:
   * **Machine Type:** `q35`
   * **BIOS:** OVMF (UEFI) com Secure Boot
   * **TPM:** v2.0
   * **SCSI Controller:** `virtio-scsi-single`
   * **Disco:** VirtIO Block com `discard=on` (Thin Provisioning)
4. **Anexação de ISOs:** Anexa a ISO do Windows, a ISO do VirtIO e a ISO do `autounattend.xml`.

---

## 4. Passo a Passo: Fase 2 (Manual)

Após o script finalizar a Fase 1, a VM estará criada e pronta para ser iniciada.

### 4.1. Instalação do Windows
1. Inicie a VM recém-criada através da interface web do Proxmox ou via CLI (`qm start <VMID>`).
2. Abra o console da VM (VNC ou SPICE).
3. **Não é necessário interagir.** A instalação ocorrerá de forma 100% autônoma graças ao arquivo `autounattend.xml`. O Windows será instalado, reiniciará e fará o primeiro logon automaticamente.
4. Após o primeiro logon, um script PowerShell abrirá brevemente para instalar os drivers VirtIO Guest Tools e o QEMU Guest Agent.

### 4.2. Configuração do Sistema e Aplicações
Este é o momento ideal para aplicar configurações que você deseja que todos os clones herdem:
* Instalar atualizações do Windows Update.
* Configurar regras de Firewall.
* Instalar softwares padrão (ex: agentes de monitoramento, navegadores, ferramentas de backup) [3].
* **Nota:** Não ingresse a máquina em um domínio Active Directory neste momento.

### 4.3. Instalação e Configuração do Cloudbase-Init
O Cloudbase-Init é o equivalente Windows do Cloud-Init. Ele permite que o Proxmox injete configurações (IP, hostname, senhas) quando um clone for inicializado [1].

1. Faça o download do instalador no site oficial: [Cloudbase-Init Download](https://cloudbase.it/cloudbase-init/#download).
2. Execute o instalador. Durante o assistente:
   * Escolha o usuário `Administrator`.
   * Selecione a porta serial `COM1` para logging (o script já adicionou esta porta à VM).
   * **ATENÇÃO:** Na última tela do instalador, **DESMARQUE** as opções "Run Sysprep" e "Reboot". Clique em Finish.
3. Abra o arquivo de configuração `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf` em um editor de texto (como o Notepad) e ajuste para o seguinte padrão [4]:

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
logdir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
logfile=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=COM1,115200,N,8
mtu_use_dhcp_config=false
ntp_use_dhcp_config=false
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
check_latest_version=true
plugins=cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin
```

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
./proxmox-templates.sh finalize-windows 9007
```

### O que o script de finalização faz?
1. Verifica se a VM está desligada.
2. Remove as três unidades de CD-ROM virtuais (ISOs de instalação).
3. Adiciona um novo drive Cloud-Init configurado para utilizar o storage pool definido no `config.env`.
4. Altera a ordem de boot para iniciar diretamente pelo disco SCSI (`scsi0`).
5. Converte a VM definitivamente em um Template [1].

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
