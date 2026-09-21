# Requisitos e dependências

[← Voltar ao README](../README.md)

## Hardware

| Recurso | Mínimo | Recomendado | Observação |
|---|---|---|---|
| CPU | 2 núcleos | 4 núcleos ou mais | O reconhecimento facial do Immich é pesado nas primeiras horas |
| RAM | 6 GB | 8 GB ou mais | Valores do Immich; a stack de mídia soma ao total |
| Sistema + configs + banco | SSD | SSD | O Postgres do Immich exige disco **local** (nunca compartilhamento de rede) |
| Mídia e fotos | HD ou SSD | HD grande (2 TB+) | As miniaturas e vídeos convertidos do Immich acrescentam 10% a 20% ao tamanho da biblioteca |
| Rede | Wi-Fi | Cabo Gigabit | Reserve um IP fixo para o servidor no roteador |

CPU x86-64: o container de aprendizado de máquina do Immich v3 exige o nível **x86-64-v2** (CPUs de 2012 em diante). Para conferir (glibc 2.33 ou superior):

```bash
/lib64/ld-linux-x86-64.so.2 --help | grep -E "x86-64-v[234]"
```

## Dependências de software

| Dependência | Para que serve | Como conferir |
|---|---|---|
| Linux 64-bit (Ubuntu Server 22.04/24.04 ou Debian 12+) | Sistema do servidor | `cat /etc/os-release` |
| **Docker Engine** | Executa os containers | `docker --version` |
| **Docker Compose v2** (plugin `docker compose`) | Sobe cada projeto a partir do `docker-compose.yml`. O antigo `docker-compose` (com hífen) **não** é suportado pelo Immich | `docker compose version` |
| **git** | Clonar e versionar este repositório | `git --version` |
| *Opcional:* **make** (GNU) | Atalhos `make up`, `make stop` e `make clean` (veja a [seção Atalhos com `make`](atalhos-make.md)) | `make --version` |
| **curl** | Baixar arquivos e chaves | `curl --version` |
| **openssl** | Gerar a senha do banco | `openssl version` |
| `ca-certificates` | Validar conexões HTTPS | (instalado com o `curl`) |
| *Opcional:* **Tailscale** | Acesso remoto seguro, sem abrir portas | `tailscale version` |
| *Opcional:* **GitHub CLI (`gh`)** | Login no GitHub (repositório privado) | `gh --version` |
| *Opcional:* driver de GPU | Transcodificação por hardware no Jellyfin (Intel/AMD: `/dev/dri`) | `ls /dev/dri` |

## Instalação das dependências

### Ubuntu / Debian: pacotes básicos

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl openssl ca-certificates make
```

### Ubuntu: Docker Engine + Compose (repositório oficial do Docker)

Método da [documentação oficial](https://docs.docker.com/engine/install/ubuntu/):

```bash
# Chave GPG do Docker
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Repositório
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Instalação
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

> **Debian:** use o mesmo procedimento trocando `ubuntu` por `debian` na URL da chave e em `URIs` ([documentação](https://docs.docker.com/engine/install/debian/)).
> **Fedora, Arch e outras:** veja a [página de instalação do Docker](https://docs.docker.com/engine/install/). No Arch: `sudo pacman -S docker docker-compose git curl openssl make`.

Teste e configure para iniciar com o sistema:

```bash
sudo docker run hello-world
sudo systemctl enable --now docker
```

Para usar `docker` sem `sudo` (saia e entre na sessão, ou rode `newgrp docker`):

```bash
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

> ⚠️ Quem está no grupo `docker` tem poder equivalente a **root** na máquina. Adicione apenas usuários de confiança.

### Opcional: Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

O `tailscale up` mostra um link para autenticar no navegador. Detalhes na [seção Acesso remoto](operacao-backup-acesso.md#acesso-remoto).
