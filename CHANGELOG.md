# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo. O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Corrigido

- O fluxo Windows deixou de assumir `local:iso`: o storage das ISOs agora é configurado por `WINDOWS_ISO_STORAGE`, usado para anexar e remover o ISO `autounattend` corretamente.
- O caminho de host das ISOs é resolvido por `pvesm path`, mantendo `DOWNLOAD_DIR` alinhado ao storage configurado.
- A ordem das mídias Windows foi corrigida para manter a ISO VirtIO em `ide1`/`E:` e o `autounattend` em `ide2`; o Windows PE agora carrega somente `vioscsi`, evitando a falha `Windows Setup could not install one or more boot-critical drivers`.

## [1.6.0] - 2026-09-29

### Adicionado

- Suporte ao Windows Server 2019 Evaluation com o comando `./proxmox-templates.sh win-2019`.
- VMID padrão `9012` e nome `win-server-2019-template`.
- Geração de `autounattend.xml` usando os drivers VirtIO `2k19` para SCSI, rede, balloon e storage.
- Cobertura automatizada para o mapeamento `Windows Server 2019 -> ostype=win10 -> VirtIO 2k19`.

### Alterado

- O fluxo `windows` e o preflight global agora incluem Windows Server 2019, 2022 e 2025.
- A documentação Windows e o guia de testes foram atualizados para as três versões suportadas.

### Referências técnicas

- Proxmox Wiki: `Windows 2019 guest best practices`.
- Proxmox Forum: implementação comunitária de templates 2019/2022/2025 com Cloudbase-Init.

## [1.5.0] - 2026-09-28

### Adicionado

- Arquivo `config.local.env.example` para manter configurações e credenciais específicas do cluster fora do Git.
- Comando `preflight` somente leitura para validar PVE, storages, conteúdo `snippets`, bridge e VMIDs.
- Validação de storage ativo e resolução do caminho de snippets por volume ID completo (`<storage>:snippets/<arquivo>`).
- Testes automatizados para inventário cluster-wide, storage de snippets, importação RBD e segurança do fluxo Windows.

### Alterado

- A importação de disco agora anexa o volume real registrado como `unused0`, sem assumir o nome interno do volume RBD.
- O script carrega opcionalmente `config.local.env` após `config.env`.
- Configurações específicas do cluster e credenciais passam a residir em `config.local.env`, evitando conflitos de `git pull` no arquivo versionado.

### Segurança

- O script não remove VMs ou templates existentes; qualquer VMID ocupado no inventário global do cluster bloqueia a execução antes da criação.
- O inventário global precisa ser um JSON válido; falhas ou respostas inválidas bloqueiam a execução.
- `config.local.env` foi adicionado ao `.gitignore` para evitar vazamento de credenciais e conflitos em `git pull`.
- O ISO `autounattend` e os arquivos temporários com a senha Windows em texto claro são removidos ao finalizar o template.
- Durante a instalação Windows, o ISO `autounattend` continua sensível e deve usar credencial temporária exclusiva até a finalização.
- `finalize-windows` valida VMID, nome, conjunto exato de tags, volume ISO esperado e estado antes de modificar uma VM.
- XML e ISO do `autounattend` são criados com permissões restritivas, e valores de credenciais recebem escape XML.

### Corrigido

- Corrigida a lógica de instalação do pacote `genisoimage` quando a dependência Windows não está presente.

## [1.4.0] - 2026-08-12

### Adicionado

**Suporte a Oracle Linux 8.10 e 9.8:** Adicionados dois novos templates para Oracle Linux, utilizando as cloud images oficiais KVM da Oracle (yum.oracle.com). Os templates utilizam VMIDs 9010 (OL8) e 9011 (OL9), kernel UEK7 e seguem o mesmo padrão de configuração dos demais templates Linux.

- **Oracle Linux 8.10** (VMID 9010): `OL8U10_x86_64-kvm-b287.qcow2`
- **Oracle Linux 9.8** (VMID 9011): `OL9U8_x86_64-kvm-b293.qcow2`
- Novos comandos: `./proxmox-templates.sh oracle-8` e `./proxmox-templates.sh oracle-9`

## [1.3.3] - 2026-04-29

### Corrigido

**Correção do erro 'volume local:snippets/qemu-guest-agent.yaml does not exist' ao clonar templates:** O snippet Cloud-Init para instalação do qemu-guest-agent era armazenado no storage `local`, que é específico de cada nó. Em clusters multi-nó, ao clonar o template em outro nó, o snippet não era encontrado. Agora o snippet é armazenado no storage compartilhado configurado em `SNIPPETS_STORAGE`, garantindo disponibilidade em todos os nós do cluster.

### Adicionado

**Nova variável `SNIPPETS_STORAGE` no config.env:** Permite configurar qual storage compartilhado será usado para armazenar os snippets Cloud-Init. O storage deve ter o content type `snippets` habilitado; ao alterá-lo, preserve os demais tipos de conteúdo já configurados.

## [1.3.2] - 2026-04-28

### Corrigido

**Correção do erro 'shrinking disks is not supported' no PVE 9.x:** O script tentava redimensionar o disco para o tamanho configurado em `LINUX_DISK_RESIZE` sem verificar se o disco atual já era maior. No PVE 9.x, o `qm disk resize` retorna erro fatal ao tentar diminuir um disco. Agora o script obtém o tamanho atual do disco via `qm config`, compara com o tamanho desejado e só executa o resize se o disco atual for menor.

### Alterado

**Tamanho padrão de disco aumentado de 8G para 32G:** O valor padrão de `LINUX_DISK_RESIZE` no `config.env` foi aumentado de 8G para 32G, pois várias cloud images (CentOS, Rocky) já possuem discos virtuais maiores que 8G.

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

**Interface serial ausente nos templates Windows:** A criação de VMs Windows não incluía as portas seriais (`--serial0 socket` e `--serial1 socket`). Elas foram adicionadas para logging e diagnóstico do Cloudbase-Init em COM1/COM2. O recebimento de metadados continua sendo feito pelo drive Cloud-Init/ConfigDrive.

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
