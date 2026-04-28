# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo. O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [1.3.1] - 2026-04-28

### Corrigido

**Correção crítica na função download_image (wget poluindo stdout):** O comando wget usava `2>&1` que redirecionava a barra de progresso (stderr) para stdout. Quando a função era chamada via `image_path=$(download_image ...)`, toda a barra de progresso era capturada junto com o caminho do arquivo, causando `Argument list too long` no `basename` e falha na validação do arquivo com `-f`. Removido o `2>&1` para manter stdout limpo.

**Correção na função import_disk_image (output do qm importdisk):** O output do `qm importdisk` agora é capturado em variável e redirecionado para stderr, evitando poluição do stdout. Em caso de falha, o output completo do comando é exibido no log de erro para facilitar o diagnóstico.

## [1.3.0] - 2026-04-28

### Adicionado

**Suporte ao Ubuntu 26.04 LTS (Resolute Raccoon):** Adicionado novo template para a versão mais recente do Ubuntu Server LTS, lançada pela Canonical em abril de 2026. A cloud image é obtida de `https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img`. O template utiliza VMID 9009 e segue o mesmo padrão de configuração dos demais templates Linux (Cloud-Init, qemu-guest-agent via cicustom, VirtIO SCSI).

## [1.2.0] - 2026-04-28

### Adicionado

**Instalação automática do qemu-guest-agent nos templates Linux:** O script agora cria um snippet Cloud-Init (`/var/lib/vz/snippets/qemu-guest-agent.yaml`) e o aplica via `--cicustom vendor=local:snippets/qemu-guest-agent.yaml`. Isso garante que o pacote `qemu-guest-agent` seja instalado e habilitado automaticamente no primeiro boot de qualquer VM clonada a partir dos templates Linux. Anteriormente, o script apenas habilitava a opção `--agent enabled=1` na configuração da VM (lado Proxmox), mas o pacote não era instalado dentro do sistema operacional, resultando no agente inativo.

## [1.1.4] - 2026-04-27

### Corrigido

**Display configurado como QXL (SPICE) ao invés de VNC:** O script usava `--vga qxl` que requer SPICE client para acesso ao console. Alterado para `--vga std` que é compatível com o **noVNC** integrado na Web UI do Proxmox, eliminando a necessidade de software adicional para acessar o console das VMs Windows.

## [1.1.3] - 2026-04-27

### Corrigido

**Interface serial ausente nos templates Windows:** A criação de VMs Windows não incluía as portas seriais (`--serial0 socket` e `--serial1 socket`), que são necessárias para o Cloudbase-Init se comunicar com o Proxmox via Cloud-Init (porta COM1). Sem a interface serial, o Cloudbase-Init não conseguia receber as configurações de rede, hostname e credenciais. A correção adiciona ambas as portas seriais automaticamente na função `create_windows_template()`.

## [1.1.2] - 2026-04-23

### Corrigido

**Logs poluindo stdout e quebrando captura de retorno de funções:** A função `log()` enviava mensagens para stdout, o que causava a contaminação da variável `image_path` quando `download_image()` era chamada via command substitution `$(...)`. O resultado era que o caminho do arquivo ficava precedido por linhas de log, fazendo com que o teste `-f` (arquivo existe) falhasse com `Arquivo de imagem não encontrado`. A correção redireciona toda a saída de log para **stderr** (`>&2`), mantendo o stdout limpo para retornos de funções.

## [1.1.1] - 2026-04-23

### Corrigido

**Importação de disco em storage RBD/Ceph:** Corrigido o erro `scsi0: invalid format - missing key in comma-separated list property` que impedia a criação de todos os templates Linux. A função `import_disk_image()` foi reescrita para usar o comando `qm importdisk` (universal e compatível com todos os tipos de storage: RBD, LVM, ZFS, NFS, etc.) seguido de `qm set` para anexar o disco, substituindo a sintaxe `import-from` do `qm set` que falhava em storages RBD/Ceph no PVE 9.x.

### Adicionado

**Validação de imagem pré-importação:** Antes de importar o disco, o script agora verifica se o arquivo de imagem existe e se o tamanho é superior a 1MB, detectando downloads corrompidos ou incompletos antes de tentar a importação.

## [1.1.0] - 2026-04-23

### Adicionado

**Compatibilidade com Proxmox VE 8.x e 9.x:** Detecção automática da versão do Proxmox VE e QEMU em tempo de execução. O script identifica a versão do PVE (major/minor) e do QEMU, ajustando automaticamente os comandos e parâmetros utilizados. A função `pve_version_ge()` permite comparação de versões em qualquer ponto do código.

**Importação de disco inteligente:** Nova função `import_disk_image()` que utiliza o método `import-from` do `qm set` (disponível a partir do PVE 8.1) ou o método legado `qm importdisk` (para PVE 8.0), garantindo compatibilidade total com todas as versões suportadas.

**Validação de storages descontinuados:** O script agora verifica se o storage configurado é do tipo GlusterFS (removido no PVE 9) e emite um erro informativo antes de tentar criar templates.

**Comando `version`:** Novo comando que exibe a versão do PVE e QEMU detectados, além do método de importação de disco que será utilizado.

**Tags dinâmicas:** Os templates criados agora incluem uma tag com a versão do PVE (ex: `pve8`, `pve9`) para facilitar a identificação.

### Corrigido

**ShellCheck CI/CD:** Todos os warnings do ShellCheck (SC2034, SC2231) foram corrigidos. O workflow do GitHub Actions agora passa com sucesso em todos os scripts. As variáveis globais compartilhadas entre módulos receberam a diretiva `shellcheck disable=SC2034`, e a geração do `autounattend.xml` foi reescrita sem uso de `sed` intermediário.

### Alterado

O banner, o resumo de configuração e a documentação foram atualizados para refletir a compatibilidade com Proxmox VE 8.x e 9.x. A URL do repositório foi corrigida para `Lauri-Zancanaro/proxmox-templates-script`.

## [1.0.0] - 2026-04-23

### Adicionado

Lançamento inicial do projeto com as seguintes funcionalidades:

**Templates Linux (Cloud-Init):** Suporte completo para criação automatizada de templates para Ubuntu 24.04 LTS (Noble Numbat), Debian 12 (Bookworm), Debian 13 (Trixie), CentOS Stream 9, Rocky Linux 8 e Rocky Linux 9. Cada template é criado com download automático da cloud image oficial, importação do disco, configuração de hardware otimizado (VirtIO SCSI, QEMU Guest Agent, serial console) e injeção de credenciais via Cloud-Init.

**Templates Windows Server (Cloudbase-Init):** Suporte semi-automatizado para criação de templates Windows Server 2022 e Windows Server 2025. O script gera automaticamente o arquivo `autounattend.xml` para instalação desatendida, configura hardware otimizado para Windows (q35, OVMF/UEFI, TPM 2.0, Secure Boot) e fornece instruções detalhadas para os passos manuais restantes (Cloudbase-Init e Sysprep).

**Configuração Centralizada:** Arquivo `config.env` com todas as variáveis configuráveis, incluindo storage pool, bridge de rede, credenciais Cloud-Init, mapeamento de VMIDs e URLs das cloud images.

**Tratamento de Erros:** Validação de dependências, verificação de existência do storage pool, checagem de VMIDs em uso, retry automático para downloads e logging com timestamps e níveis de severidade.

**CI/CD:** Workflow do GitHub Actions com ShellCheck para análise estática de todos os scripts bash a cada push ou pull request.
