# Proxmox VE Template Scripts

Um conjunto de scripts profissionais, modulares e automatizados para a criação de templates de Máquinas Virtuais (VMs) no Proxmox VE. Este projeto suporta múltiplas distribuições Linux (utilizando Cloud-Init) e Windows Server (utilizando Cloudbase-Init), seguindo as melhores práticas recomendadas pela documentação oficial do Proxmox e pela comunidade [1] [2].

## Compatibilidade

Este script foi atualizado e testado para garantir compatibilidade total com as versões mais recentes do Proxmox VE:
*   **Proxmox VE 8.x** (QEMU 9.x)
*   **Proxmox VE 9.x** (QEMU 10.x) [3]

O script detecta automaticamente a versão do Proxmox e do QEMU instalados, ajustando comandos e parâmetros (como o método de importação de discos e validação de storages descontinuados como GlusterFS) para garantir a execução correta em cada ambiente.

## Funcionalidades

O script orquestra o download, configuração de hardware, injeção de credenciais e conversão em template para os seguintes Sistemas Operacionais:

| Sistema Operacional | VMID Padrão | Método de Automação | Formato da Imagem |
|---------------------|-------------|---------------------|-------------------|
| Ubuntu 24.04 LTS    | 9001        | Cloud-Init          | .img (qcow2)      |
| Ubuntu 26.04 LTS    | 9009        | Cloud-Init          | .img (qcow2)      |
| Debian 12           | 9002        | Cloud-Init          | .qcow2            |
| Debian 13           | 9003        | Cloud-Init          | .qcow2            |
| CentOS Stream 9     | 9004        | Cloud-Init          | .qcow2            |
| Rocky Linux 8       | 9005        | Cloud-Init          | .qcow2            |
| Rocky Linux 9       | 9006        | Cloud-Init          | .qcow2            |
| Windows Server 2022 | 9007        | Cloudbase-Init      | Instalação ISO    |
| Windows Server 2025 | 9008        | Cloudbase-Init      | Instalação ISO    |

## Arquitetura do Projeto

A solução foi projetada de forma modular para facilitar a manutenção e escalabilidade:

*   **`proxmox-templates.sh`**: O script principal (entrypoint) que orquestra a execução.
*   **`config.env`**: Arquivo de configuração centralizado contendo variáveis como storage, rede, credenciais e URLs.
*   **`scripts/utils.sh`**: Funções utilitárias de log, detecção de versão PVE, validação e tratamento de erros.
*   **`scripts/linux-templates.sh`**: Lógica de criação para templates Linux.
*   **`scripts/windows-templates.sh`**: Lógica de criação para templates Windows Server.

## Pré-requisitos

1.  Um nó ou cluster rodando **Proxmox VE 8.x ou 9.x**.
2.  Acesso root ao shell do Proxmox.
3.  Conexão com a internet para o download das cloud images e pacotes.
4.  Espaço em disco suficiente no storage pool configurado.

## Como Usar

### 1. Clonar e Configurar

Clone o repositório diretamente no seu servidor Proxmox:

```bash
git clone https://github.com/Lauri-Zancanaro/proxmox-templates-script.git
cd proxmox-templates-script
```

Edite o arquivo de configuração `config.env` para adequar ao seu ambiente:

```bash
nano config.env
```

**Principais variáveis a revisar:**
*   `STORAGE_POOL`: O nome do storage onde os discos serão alocados (ex: `local-lvm`, `cephfs-lvm`, `local-zfs`).
*   `BRIDGE_NET`: A interface de rede do Proxmox (ex: `vmbr0`).
*   `CI_USER` e `CI_PASSWORD`: Credenciais padrão que serão injetadas via Cloud-Init.

### 2. Verificar Ambiente

Antes de iniciar, você pode verificar se o script detecta corretamente a versão do seu Proxmox:

```bash
./proxmox-templates.sh version
```

### 3. Executar a Criação de Templates Linux

Para criar todos os templates Linux suportados de uma só vez:

```bash
./proxmox-templates.sh linux
```

Para criar um template específico (exemplo: apenas Ubuntu 24.04):

```bash
./proxmox-templates.sh ubuntu-2404
```

### 4. Executar a Criação de Templates Windows Server

A criação de templates Windows é um processo **semi-automatizado**, pois a Microsoft não fornece imagens Cloud prontas. O script automatiza grande parte do processo gerando um arquivo `autounattend.xml` [4].

> Para um guia completo e detalhado com todas as etapas, configuração do Cloudbase-Init, Sysprep e troubleshooting, consulte a documentação dedicada: **[docs/WINDOWS-TEMPLATES.md](docs/WINDOWS-TEMPLATES.md)**.

**Resumo dos passos:**
1.  Baixe manualmente a ISO de avaliação do Windows Server desejado (2022 ou 2025) do Microsoft Evaluation Center.
2.  Coloque a ISO no diretório de templates do Proxmox (padrão: `/var/lib/vz/template/iso/`). O nome do arquivo deve conter o ano ("2022" ou "2025").
3.  Execute o script:
    ```bash
    ./proxmox-templates.sh win-2022
    ```
4.  O script criará a VM e anexará a ISO do Windows, a ISO de drivers VirtIO e a ISO do `autounattend.xml` gerada automaticamente.
5.  Inicie a VM no Proxmox e abra o console. A instalação do Windows ocorrerá de forma autônoma.
6.  Após o Windows iniciar e o script de pós-instalação (que instala os drivers VirtIO) concluir, instale manualmente o [Cloudbase-Init](https://cloudbase.it/cloudbase-init/) e execute o Sysprep (`/generalize /oobe /shutdown`).
7.  Quando a VM desligar, finalize a conversão para template:
    ```bash
    ./proxmox-templates.sh finalize-windows 9007
    ```

## Utilizando os Templates Criados

Após a criação, você pode clonar rapidamente novas VMs a partir dos templates.

**Via Interface Web (GUI):**
1. Clique com o botão direito no template desejado e selecione "Clone".
2. Escolha "Linked Clone" (rápido, economiza espaço) ou "Full Clone".
3. Vá na aba "Cloud-Init" da nova VM, ajuste IP, chaves SSH e clique em "Regenerate Image".
4. Inicie a VM.

**Via Linha de Comando (CLI):**
```bash
# Clonar a VM (ex: clonando o template 9001 para a nova VM 100)
qm clone 9001 100 --name meu-novo-servidor

# Configurar IP e Gateway via Cloud-Init
qm set 100 --ipconfig0 ip=10.0.0.50/24,gw=10.0.0.1

# Configurar chave SSH (recomendado para produção)
qm set 100 --sshkeys ~/.ssh/id_rsa.pub

# Iniciar a VM
qm start 100
```

## Boas Práticas Implementadas

Este script incorpora diversas boas práticas consolidadas:
*   **Hardware Otimizado:** Utiliza `virtio-scsi-pci` (ou `virtio-scsi-single`) para máxima performance de I/O [1].
*   **QEMU Guest Agent:** Habilitado por padrão em todos os templates para comunicação bidirecional hypervisor-guest.
*   **Thin Provisioning:** Ativação do parâmetro `discard=on` no disco e `fstrim_cloned_disks=1` no Guest Agent para recuperar espaço em disco.
*   **Segurança Windows:** Configuração automática de TPM 2.0, UEFI (OVMF) e Secure Boot para templates Windows Server [4].
*   **Compatibilidade Multi-versão:** Adaptação automática de comandos (`import-from` vs `importdisk`) baseada na versão do Proxmox detectada.
*   **Tratamento de Erros:** Validação de dependências, checagem de existência do Storage Pool e verificação de VMIDs em uso antes de qualquer operação destrutiva.

## Versões e Changelog

Atualmente o projeto está na versão **v1.3.3**. 

Para ver o histórico completo de alterações, novas funcionalidades e correções de bugs de cada versão, consulte o arquivo **[CHANGELOG.md](CHANGELOG.md)**.

As versões são publicadas utilizando o padrão de [Versionamento Semântico](https://semver.org/lang/pt-BR/). Você pode acompanhar as [Releases oficiais no GitHub](https://github.com/Lauri-Zancanaro/proxmox-templates-script/releases) para baixar versões estáveis específicas.

## CI/CD e Versionamento

Este projeto inclui um workflow do GitHub Actions (`.github/workflows/shellcheck.yml`) que executa automaticamente o `shellcheck` em todos os scripts `.sh` a cada push ou pull request, garantindo a qualidade e segurança do código bash. Todos os scripts são validados para rodar sem warnings ou erros.

## Documentação Adicional

| Documento | Descrição |
|-----------|----------|
| [docs/WINDOWS-TEMPLATES.md](docs/WINDOWS-TEMPLATES.md) | Guia completo para criação de templates Windows Server (Cloudbase-Init, Sysprep, troubleshooting) |

## Referências

[1] Proxmox VE Documentation: "qm(1) - QEMU/KVM Virtual Machine Manager". Disponível em: https://pve.proxmox.com/pve-docs/qm.1.html
[2] Proxmox Wiki: "Cloud-Init Support". Disponível em: https://pve.proxmox.com/wiki/Cloud-Init_Support
[3] Proxmox Wiki: "Roadmap - Proxmox VE 9.0". Disponível em: https://pve.proxmox.com/wiki/Roadmap#9.0-known-issues
[4] ComputingForGeeks: "Create Windows Server 2022 Template in Proxmox VE". Disponível em: https://computingforgeeks.com/windows-server-2022-template-proxmox/
