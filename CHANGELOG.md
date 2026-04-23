# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo. O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [1.0.0] - 2026-04-23

### Adicionado

Lançamento inicial do projeto com as seguintes funcionalidades:

**Templates Linux (Cloud-Init):** Suporte completo para criação automatizada de templates para Ubuntu 24.04 LTS (Noble Numbat), Debian 12 (Bookworm), Debian 13 (Trixie), CentOS Stream 9, Rocky Linux 8 e Rocky Linux 9. Cada template é criado com download automático da cloud image oficial, importação do disco, configuração de hardware otimizado (VirtIO SCSI, QEMU Guest Agent, serial console) e injeção de credenciais via Cloud-Init.

**Templates Windows Server (Cloudbase-Init):** Suporte semi-automatizado para criação de templates Windows Server 2022 e Windows Server 2025. O script gera automaticamente o arquivo `autounattend.xml` para instalação desatendida, configura hardware otimizado para Windows (q35, OVMF/UEFI, TPM 2.0, Secure Boot) e fornece instruções detalhadas para os passos manuais restantes (Cloudbase-Init e Sysprep).

**Configuração Centralizada:** Arquivo `config.env` com todas as variáveis configuráveis, incluindo storage pool, bridge de rede, credenciais Cloud-Init, mapeamento de VMIDs e URLs das cloud images.

**Tratamento de Erros:** Validação de dependências, verificação de existência do storage pool, checagem de VMIDs em uso, retry automático para downloads e logging com timestamps e níveis de severidade.

**CI/CD:** Workflow do GitHub Actions com ShellCheck para análise estática de todos os scripts bash a cada push ou pull request.
