# Guia de Testes e Validação — Proxmox Template Scripts v1.6.0

Este documento descreve como validar a versão v1.6.0 em desenvolvimento/homologação antes de criar templates no ambiente de produção. O fluxo prioriza pré-validação somente leitura, VMIDs isolados e separação entre Linux e Windows.

## 1. Princípios de segurança

- Use `config.local.env`; não grave credenciais reais em `config.env`.
- Reserve uma faixa de VMIDs exclusiva para homologação.
- Execute `preflight` antes de qualquer criação.
- O script não remove VMs ou templates existentes. Um VMID ocupado bloqueia a operação.
- Não execute `all` para um primeiro teste. Valide um Linux por vez; trate Windows separadamente.
- Confirme nome, tags, nó e discos antes de remover manualmente qualquer recurso de teste.

## 2. Preparação do ambiente

### 2.1 Obter a versão

```bash
git clone https://github.com/Lauri-Zancanaro/proxmox-templates-script.git
cd proxmox-templates-script
git checkout v1.6.0
```

Em um clone já existente:

```bash
git pull --ff-only origin main
git checkout v1.6.0
```

### 2.2 Criar configuração local

```bash
cp config.local.env.example config.local.env
chmod 600 config.local.env
nano config.local.env
```

Exemplo para homologação com VMIDs `9101–9112`:

```bash
STORAGE_POOL="vm-nvme"
SNIPPETS_STORAGE="storage-nvme"
WINDOWS_ISO_STORAGE="local"
BRIDGE_NET="vmbr901"

CI_USER="usuario-teste"
CI_PASSWORD='Informe_Sua_Senha'
CI_NETWORK="dhcp"

VMID_UBUNTU_2404=9101
VMID_DEBIAN_12=9102
VMID_DEBIAN_13=9103
VMID_CENTOS_STREAM_9=9104
VMID_ROCKY_8=9105
VMID_ROCKY_9=9106
VMID_WIN_2022=9107
VMID_WIN_2025=9108
VMID_UBUNTU_2604=9109
VMID_ORACLE_8=9110
VMID_ORACLE_9=9111
VMID_WIN_2019=9112
```

Antes de escolher a faixa, consulte o inventário global do cluster:

```bash
pvesh get /cluster/resources --type vm --output-format json-pretty
```

## 3. Pré-validação somente leitura

```bash
./proxmox-templates.sh version
./proxmox-templates.sh preflight
```

O `preflight` deve confirmar:

- PVE 8.x ou 9.x detectado;
- storage de discos ativo;
- bridge existente e ativa no nó;
- storage compartilhado com conteúdo `snippets`;
- todos os VMIDs configurados livres no inventário global do cluster.

Se a consulta do inventário falhar ou retornar JSON inválido, a validação deve abortar sem criar diretórios, discos ou VMs.

## 4. Teste Linux controlado

Comece com um único template:

```bash
./proxmox-templates.sh debian-12
```

Verificações esperadas:

```bash
qm config 9102
pvesm list vm-nvme --vmid 9102
pvesm path storage-nvme:snippets/qemu-guest-agent.yaml
```

Confirme no `qm config 9102`:

- `template: 1`;
- disco `scsi0` em `vm-nvme`;
- drive Cloud-Init;
- `cicustom` apontando para `storage-nvme:snippets/qemu-guest-agent.yaml`;
- `agent: enabled=1`;
- rede ligada à bridge escolhida.

## 5. Teste de clone e Cloud-Init

Escolha um VMID livre para o clone, por exemplo `9199`, e confirme-o no inventário global antes de criar:

```bash
pvesh get /cluster/resources --type vm --output-format json-pretty
qm clone 9102 9199 --name teste-debian --full 1 --storage vm-nvme
qm set 9199 --ipconfig0 ip=dhcp
qm start 9199
```

Valide:

- boot sem erro;
- hostname e rede aplicados pelo Cloud-Init;
- acesso por chave SSH ou credencial de teste;
- QEMU Guest Agent ativo dentro do clone:

```bash
qm agent 9199 ping
```

O snippet permanece uma dependência enquanto estiver referenciado por `cicustom`; portanto `storage-nvme` deve estar disponível em todos os nós onde a VM puder iniciar.

## 6. Teste de proteção de VMID

Com o template de teste existente, execute novamente:

```bash
./proxmox-templates.sh debian-12
```

Resultado esperado: o script deve detectar o VMID ocupado no cluster e abortar antes de criar ou remover recursos.

## 7. Teste Windows separado

A preparação Windows exige ISOs da Microsoft e uma etapa manual com Cloudbase-Init/Sysprep. Consulte [WINDOWS-TEMPLATES.md](WINDOWS-TEMPLATES.md).

Antes de executar:

1. Coloque as ISOs 2019/2022/2025 no diretório definido por `DOWNLOAD_DIR`, com o ano no nome, e confirme que `WINDOWS_ISO_STORAGE` publica esse diretório.
2. Defina uma senha temporária exclusiva em `config.local.env`.
3. Execute `./proxmox-templates.sh preflight`.
4. Crie uma versão por vez:

```bash
./proxmox-templates.sh win-2019
# Depois de instalar Cloudbase-Init e executar Sysprep:
./proxmox-templates.sh finalize-windows 9112
```

`finalize-windows` deve recusar VMID, nome, tags ou ISO diferentes dos esperados, incluindo storage incorreto. Após a conversão, o ISO `autounattend` contendo a senha temporária é removido do storage configurado.

## 8. Limpeza manual do laboratório

A limpeza é intencionalmente manual e destrutiva. Antes de remover qualquer recurso, confirme que ele pertence ao laboratório:

```bash
qm config 9199
qm config 9102
```

Somente após revisar nome, tags e discos e obter a autorização operacional aplicável:

```bash
qm stop 9199
qm destroy 9199 --purge
qm destroy 9102 --purge
```

Nunca reutilize esses comandos com VMIDs de produção sem uma revisão explícita.

## 9. Validação do repositório

Em uma estação de desenvolvimento com ShellCheck:

```bash
find . -name '*.sh' -type f -print0 | xargs -0 -n1 shellcheck --severity=warning --shell=bash
bash -n config.env config.local.env.example proxmox-templates.sh
bash tests/test-utils.sh
bash tests/test-windows.sh
```

A mesma suíte é executada pelo GitHub Actions em pushes e pull requests relevantes.
