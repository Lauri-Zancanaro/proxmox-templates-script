# Guia de Testes e Validação - Proxmox Template Scripts

Este documento detalha como validar as alterações da versão v1.1.1 e testar o script de forma segura em um ambiente de desenvolvimento (dev/homologação) antes de aplicá-lo em produção. O objetivo principal é garantir que a nova função de importação de discos funcione corretamente com o storage RBD/Ceph ou qualquer outro tipo de storage disponível no seu cluster.

## 1. Preparação do Ambiente de Teste

Para realizar testes seguros sem afetar os templates de produção existentes (VMIDs 9001 a 9008), recomendamos a criação de um arquivo de configuração específico para desenvolvimento.

### 1.1 Clonar a Versão Mais Recente

Primeiro, garanta que você possui a versão com a correção mais recente (v1.1.1) no seu servidor Proxmox de desenvolvimento.

```bash
# Clone o repositório ou atualize o existente
git clone https://github.com/Lauri-Zancanaro/proxmox-templates-script.git
cd proxmox-templates-script
git checkout v1.1.1
```

### 1.2 Criar Configuração Isolada (config-dev.env)

Crie uma cópia do arquivo de configuração e altere os VMIDs para uma faixa diferente (por exemplo, 9100+), garantindo isolamento total.

```bash
cp config.env config-dev.env
nano config-dev.env
```

**Alterações recomendadas no `config-dev.env`:**
- `VMID_UBUNTU_2404=9101`
- `VMID_DEBIAN_12=9102`
- `STORAGE_POOL="seu-storage-de-teste"` (pode ser o `cephfs-lvm` ou um storage local temporário)

Para testar usando este arquivo isolado, basta criar um link simbólico ou sobrescrever temporariamente o `config.env` original durante os testes:

```bash
cp config-dev.env config.env
```

## 2. Cenários de Teste Recomendados

Os testes abaixo cobrem as funcionalidades principais e as correções específicas implementadas na versão v1.1.1.

### Cenário A: Validação da Correção Crítica (RBD/Ceph)

Este teste valida se a substituição da sintaxe `import-from` pelo comando `qm importdisk` resolveu o erro `scsi0: invalid format`.

**Passos:**
1. Execute a criação de um único template leve (ex: Debian 12).
   ```bash
   ./proxmox-templates.sh debian-12
   ```
2. **Resultado Esperado:** O script deve baixar a imagem, criar a VM e exibir o log `[VMID:9102] Executando: qm importdisk 9102 debian-12-genericcloud-amd64.qcow2 cephfs-lvm`.
3. **Verificação de Sucesso:** A VM 9102 deve ser criada sem o erro `invalid format` e convertida para template com sucesso.

### Cenário B: Validação de Integridade de Imagem (Nova Funcionalidade)

Este teste valida a nova camada de segurança que impede a importação de imagens corrompidas (tamanho inferior a 1MB).

**Passos:**
1. Simule um download corrompido criando um arquivo vazio no diretório de downloads.
   ```bash
   mkdir -p /var/lib/vz/template/iso
   touch /var/lib/vz/template/iso/debian-13-genericcloud-amd64.qcow2
   ```
2. Tente criar o template correspondente.
   ```bash
   ./proxmox-templates.sh debian-13
   ```
3. **Resultado Esperado:** O script deve detectar que o arquivo é muito pequeno e abortar a operação com a mensagem: `Arquivo de imagem muito pequeno (0 bytes). Download pode ter falhado.`

### Cenário C: Teste de Provisionamento (Clone)

O teste final garante que o template criado é totalmente funcional e o Cloud-Init injeta as configurações corretamente.

**Passos:**
1. Clone o template recém-criado (ex: VMID 9102) para uma nova VM de teste (ex: VMID 9199).
   ```bash
   qm clone 9102 9199 --name teste-debian --full 1
   ```
2. Inicie a VM clonada.
   ```bash
   qm start 9199
   ```
3. Acesse o console da VM ou aguarde a obtenção do IP.
   ```bash
   qm terminal 9199
   ```
4. **Resultado Esperado:** A VM deve fazer boot corretamente, redimensionar o disco raiz e aceitar o login com o usuário e senha definidos no `config.env` (`CI_USER` e `CI_PASSWORD`).

## 3. Limpeza do Ambiente de Teste

Após a validação bem-sucedida, você pode remover os templates de teste criados na faixa 9100+.

```bash
# Remover a VM clonada
qm stop 9199
qm destroy 9199 --purge

# Remover o template de teste
qm destroy 9102 --purge
```

Restabeleça o arquivo de configuração original para preparar o ambiente para a execução em produção.

```bash
git checkout config.env
```

---
*Documentação gerada para garantir a confiabilidade dos deploys em servidores Proxmox, alinhada com as boas práticas de validação em ambientes de desenvolvimento antes da aplicação em produção.*
