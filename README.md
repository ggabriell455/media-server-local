# midia-server-local

Servidor doméstico self-hosted com **streaming de filmes e séries**, **backup de fotos** e **gerenciamento de containers**, tudo rodando em Docker no seu próprio hardware, sem mensalidade e sem enviar seus dados para terceiros.

Este repositório é a **fonte da verdade** dos arquivos Docker: os `docker-compose.yml` ficam versionados aqui, e os segredos de cada máquina ficam em arquivos `.env` locais (ignorados pelo Git).

## Sumário

1. [Início rápido](#1-início-rápido)
2. [Aplicações](#2-aplicações)
3. [Como tudo se conecta](#3-como-tudo-se-conecta)
4. [Estrutura do repositório e das pastas](#4-estrutura-do-repositório-e-das-pastas)
5. [Requisitos e dependências](#5-requisitos-e-dependências)
6. [Setup passo a passo](#6-setup-passo-a-passo)
7. [Configuração inicial de cada aplicação](#7-configuração-inicial-de-cada-aplicação)
8. [Operação do dia a dia](#8-operação-do-dia-a-dia)
9. [Backup](#9-backup)
10. [Acesso remoto](#10-acesso-remoto)
11. [Segurança](#11-segurança)
12. [Solução de problemas](#12-solução-de-problemas)
13. [Fluxo de trabalho com Git](#13-fluxo-de-trabalho-com-git)
14. [Referências](#14-referências)
15. [Aviso legal](#15-aviso-legal)

---

## 1. Início rápido

Para quem já tem Linux com Docker e Compose instalados (senão, veja a [seção 5](#5-requisitos-e-dependências)):

```bash
# 1. Pastas de dados e permissões (ajuste 1000:1000 se o seu `id` for outro)
sudo mkdir -p /srv/data/torrents/{movies,tv} /srv/data/media/{movies,tv} \
  /srv/config/{qbittorrent,prowlarr,sonarr,radarr,bazarr,jellyfin,seerr,dockhand} \
  /srv/photos/immich /srv/stacks
sudo chown -R 1000:1000 /srv/data /srv/config /srv/photos /srv/stacks

# 2. Clonar este repositório (privado: veja "Autenticação no GitHub" na seção 6)
git clone https://github.com/ggabriell455/midia-server-local.git /srv/stacks
cd /srv/stacks

# 3. Criar e preencher os .env
for p in media immich dockhand; do cp "$p/.env.example" "$p/.env"; done
sed -i "s/^PUID=.*/PUID=$(id -u)/; s/^PGID=.*/PGID=$(id -g)/" media/.env dockhand/.env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" dockhand/.env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(openssl rand -hex 16)/" immich/.env

# 4. Validar e subir
for p in media immich dockhand; do (cd "$p" && docker compose config -q && echo "$p: OK"); done
for p in dockhand media immich; do (cd "/srv/stacks/$p" && docker compose up -d); done
```

Depois é só configurar cada aplicação pelo navegador ([seção 7](#7-configuração-inicial-de-cada-aplicação)).

---

## 2. Aplicações

| Aplicação | Categoria | Finalidade | Porta | Projeto |
|---|---|---|---|---|
| [Jellyfin](#jellyfin) | Mídia | Servidor de streaming (reproduz) | 8096 | `media` |
| [Radarr](#radarr) | Automação | Gerencia **filmes** | 7878 | `media` |
| [Sonarr](#sonarr) | Automação | Gerencia **séries** | 8989 | `media` |
| [Bazarr](#bazarr) | Automação | Baixa e sincroniza **legendas** | 6767 | `media` |
| [Prowlarr](#prowlarr) | Automação | Central de **indexadores** | 9696 | `media` |
| [qBittorrent](#qbittorrent) | Download | Cliente de torrent | 8080 (web), 6881 (peers) | `media` |
| [Seerr](#seerr) | Pedidos | Interface para **pedir** filmes/séries | 5055 | `media` |
| [Immich](#immich) | Fotos | Backup e galeria de fotos/vídeos | 2283 | `immich` |
| [Dockhand](#dockhand) | Administração | Interface web para o Docker | 3000 | `dockhand` |

O conjunto Radarr, Sonarr, Bazarr e Prowlarr é conhecido como **stack \*arr**.

### Jellyfin

- **O que é:** servidor de mídia open source e gratuito, alternativa ao Plex e ao Emby. Sem conta obrigatória e sem telemetria.
- **Para que serve:** organiza sua biblioteca com capas, sinopses, elenco e legendas, e transmite para TV, celular, navegador, etc. Converte (transcodifica) o vídeo quando o dispositivo não suporta o formato original.
- **Papel no ecossistema:** só **reproduz**. Quem traz os arquivos para a pasta é o Radarr/Sonarr. A pasta de mídia é montada como **somente leitura** (`:ro`), então o Jellyfin não consegue apagar seus arquivos.
- **Dados:** configuração em `/srv/config/jellyfin`; mídia em `/srv/data/media`.

### Radarr

- **O que é:** gerenciador automático de **filmes**.
- **Para que serve:** você adiciona um filme à lista. O Radarr procura nos indexadores, manda o cliente de torrent baixar, **renomeia** e **move (via hardlink)** o arquivo para `/data/media/movies`. Também troca por versões de melhor qualidade quando aparecem.
- **Depende de:** Prowlarr (busca), qBittorrent (download).

### Sonarr

- **O que é:** o equivalente do Radarr para **séries**.
- **Para que serve:** acompanha as séries que você segue, detecta episódios novos, baixa, renomeia e organiza em `/data/media/tv` (uma pasta por série/temporada).
- **Depende de:** Prowlarr, qBittorrent.

### Bazarr

- **O que é:** gerenciador de **legendas**, companheiro do Sonarr e do Radarr.
- **Para que serve:** lê as bibliotecas do Sonarr/Radarr, descobre o que está sem legenda no idioma desejado (ex.: português do Brasil) e baixa de provedores de legenda. Salva ao lado do vídeo, onde o Jellyfin encontra.
- **Depende de:** Sonarr e Radarr. Precisa de escrita em `/data/media`.

### Prowlarr

- **O que é:** gerenciador central de **indexadores** (os sites/trackers onde a busca é feita).
- **Para que serve:** você cadastra os indexadores **uma vez** no Prowlarr, e ele os sincroniza automaticamente com Sonarr e Radarr. Sem ele, seria preciso cadastrar cada indexador em cada aplicativo.

### qBittorrent

- **O que é:** cliente de torrent com interface web.
- **Para que serve:** executa os downloads pedidos pelo Sonarr/Radarr, salvando em `/data/torrents`. Não gerencia a biblioteca final.
- **Portas:** `8080` (interface web) e `6881` TCP/UDP (conexão com outros peers).

### Seerr

- **O que é:** interface de **pedidos** para você e a família. É o sucessor unificado do Jellyseerr e do Overseerr.
- **Para que serve:** as pessoas entram com a conta do Jellyfin, procuram um filme ou série e clicam em "pedir". O Seerr envia o pedido ao Radarr/Sonarr, que cuidam do resto.
- **Depende de:** Jellyfin (login e biblioteca), Sonarr e Radarr. Roda como usuário `1000:1000` dentro do container.

### Immich

- **O que é:** alternativa self-hosted ao Google Fotos.
- **Para que serve:** backup automático de fotos e vídeos do celular, linha do tempo, álbuns compartilhados, reconhecimento facial, busca por conteúdo ("praia", "cachorro"), mapa. É **independente** do resto da stack.
- **Containers do projeto `immich`:**

  | Container | Função |
  |---|---|
  | `immich_server` | API e interface web |
  | `immich_machine_learning` | Reconhecimento facial e busca inteligente |
  | `immich_postgres` | Banco de dados (com extensão vetorial) |
  | `immich_redis` | Cache e filas (Valkey, compatível com Redis) |

- **Observação:** o `docker-compose.yml` do Immich é uma **cópia sem alterações** do compose oficial da release. Não o edite: personalize pelo `.env`.

### Dockhand

- **O que é:** interface web para administrar o Docker (na linha do Portainer).
- **Para que serve:** ver containers, logs e uso de recursos, abrir terminal, reiniciar serviços e editar stacks Compose, tudo pelo navegador.
- **Papel neste repositório:** conveniência. A fonte da verdade continua sendo o Git + `docker compose`.
- **Cuidado:** ele acessa o socket do Docker (equivale a **root** no servidor). Ative a autenticação assim que subir ([seção 7](#dockhand-1)).

---

## 3. Como tudo se conecta

```
   Família ──pede──▶ Seerr ──────────┐
                                     ▼
                             ┌───────────────┐   busca   ┌──────────┐
                             │ Sonarr/Radarr │◀─────────▶│ Prowlarr │◀── indexadores
                             └───────┬───────┘           └──────────┘
                       manda baixar  │  ▲ avisa quando terminou
                                     ▼  │
                             ┌───────────────┐
                             │  qBittorrent  │──▶ /data/torrents
                             └───────────────┘
                                     │  Sonarr/Radarr criam hardlink + renomeiam
                                     ▼
                       /data/media/{movies,tv}  ◀── Bazarr (legendas)
                                     │
                                     ▼
                                 Jellyfin ──▶ TV, celular, navegador

   Celular ──backup──▶ Immich (independente)        Dockhand ──▶ administra todos os containers
```

### Dependências entre os serviços

Ordem em que o Compose sobe os containers (`depends_on`):

| Serviço | Depende de |
|---|---|
| Sonarr, Radarr | qBittorrent, Prowlarr |
| Bazarr | Sonarr, Radarr |
| Seerr | Jellyfin, Sonarr, Radarr |
| immich-server | redis, database |

`depends_on` só controla a **ordem de início**, não garante que o outro serviço já esteja pronto. Se algo falhar logo no primeiro `up`, rode `docker compose up -d` de novo.

Os containers do mesmo projeto se enxergam pelo **nome do container**. Por isso, na configuração, use `http://sonarr:8989` em vez do IP do servidor.

### Por que existe uma única pasta `/data` (hardlinks)

Sonarr e Radarr montam a raiz `/data` **inteira**, com `torrents/` e `media/` lado a lado. Assim, ao "importar", eles criam um **hardlink**: o mesmo arquivo aparece nas duas pastas **sem ocupar espaço duas vezes**, e o torrent continua semeando. Isso só funciona se `torrents/` e `media/` estiverem **no mesmo disco/partição**. Se você usar discos separados, os arquivos são copiados e o espaço dobra.

---

## 4. Estrutura do repositório e das pastas

### Repositório

```
midia-server-local/
├── README.md
├── .gitignore               # ignora os .env (segredos)
├── media/
│   ├── docker-compose.yml   # Jellyfin, Radarr, Sonarr, Bazarr, Prowlarr, qBittorrent, Seerr
│   └── .env.example
├── immich/
│   ├── docker-compose.yml   # cópia sem alterações do compose oficial (v3.2.2)
│   └── .env.example
└── dockhand/
    ├── docker-compose.yml   # Dockhand (projeto separado de propósito)
    └── .env.example
```

Cada pasta é um **projeto Compose independente**, com seu próprio `.env`. O Dockhand fica separado porque não deve ser parado nem recriado por uma stack que ele mesmo administra.

### Pastas no servidor

```
/srv/
├── data/                    # mídia: tudo aqui dentro precisa estar no MESMO disco
│   ├── torrents/{movies,tv} #   downloads em andamento e semeando
│   └── media/{movies,tv}    #   biblioteca final (o que o Jellyfin lê)
├── config/                  # configuração de cada app (prefira SSD)
│   ├── qbittorrent/  prowlarr/  sonarr/  radarr/  bazarr/  jellyfin/  seerr/  dockhand/
│   └── immich-postgres/     #   banco do Immich (criado pelo Docker no primeiro `up`)
├── photos/
│   └── immich/              # UPLOAD_LOCATION do Immich: originais, miniaturas e dumps do banco
└── stacks/                  # este repositório clonado
```

Os caminhos vêm dos `.env`; se preferir outro layout, ajuste `CONFIG_DIR`, `DATA_DIR`, `UPLOAD_LOCATION`, `DB_DATA_LOCATION` e `STACKS_DIR`.

### Variáveis dos `.env`

| Projeto | Variável | Para que serve |
|---|---|---|
| `media` | `PUID`, `PGID` | Usuário/grupo que os containers usam para ler e gravar arquivos (veja com `id`) |
| `media` | `TZ` | Fuso horário (`America/Sao_Paulo`) |
| `media` | `CONFIG_DIR` | Raiz das configurações dos apps |
| `media` | `DATA_DIR` | Raiz dos dados (`torrents/` e `media/`) |
| `immich` | `UPLOAD_LOCATION` | Onde ficam fotos e vídeos |
| `immich` | `DB_DATA_LOCATION` | Onde fica o banco (disco local, SSD) |
| `immich` | `IMMICH_VERSION` | Versão (`v3` acompanha a série 3.x) |
| `immich` | `DB_PASSWORD` | Senha do Postgres (**obrigatória**) |
| `dockhand` | `PUID`, `PGID` | Usuário/grupo do Dockhand |
| `dockhand` | `DOCKER_GID` | GID do grupo `docker` do host (acesso ao socket) |
| `dockhand` | `DOCKHAND_DIR`, `STACKS_DIR` | Pastas montadas com o **mesmo caminho** dentro e fora do container |

---

## 5. Requisitos e dependências

### 5.1 Hardware

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

### 5.2 Dependências de software

| Dependência | Para que serve | Como conferir |
|---|---|---|
| Linux 64-bit (Ubuntu Server 22.04/24.04 ou Debian 12+) | Sistema do servidor | `cat /etc/os-release` |
| **Docker Engine** | Executa os containers | `docker --version` |
| **Docker Compose v2** (plugin `docker compose`) | Sobe cada projeto a partir do `docker-compose.yml`. O antigo `docker-compose` (com hífen) **não** é suportado pelo Immich | `docker compose version` |
| **git** | Clonar e versionar este repositório | `git --version` |
| **curl** | Baixar arquivos e chaves | `curl --version` |
| **openssl** | Gerar a senha do banco | `openssl version` |
| `ca-certificates` | Validar conexões HTTPS | (instalado com o `curl`) |
| *Opcional:* **Tailscale** | Acesso remoto seguro, sem abrir portas | `tailscale version` |
| *Opcional:* **GitHub CLI (`gh`)** | Login no GitHub (repositório privado) | `gh --version` |
| *Opcional:* driver de GPU | Transcodificação por hardware no Jellyfin (Intel/AMD: `/dev/dri`) | `ls /dev/dri` |

### 5.3 Instalação das dependências

#### Ubuntu / Debian: pacotes básicos

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl openssl ca-certificates
```

#### Ubuntu: Docker Engine + Compose (repositório oficial do Docker)

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
> **Fedora, Arch e outras:** veja a [página de instalação do Docker](https://docs.docker.com/engine/install/). No Arch: `sudo pacman -S docker docker-compose git curl openssl`.

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

#### Opcional: Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

O `tailscale up` mostra um link para autenticar no navegador. Detalhes na [seção 10](#10-acesso-remoto).

---

## 6. Setup passo a passo

### Passo 1: conferir a máquina

```bash
cat /etc/os-release      # distribuição e versão
uname -m                 # arquitetura (esperado: x86_64)
nproc                    # núcleos de CPU
free -h                  # memória
lsblk -f                 # discos, partições e sistemas de arquivos
df -h                    # espaço livre
```

### Passo 2: instalar as dependências

Siga a [seção 5.3](#53-instalação-das-dependências) e confirme:

```bash
docker --version && docker compose version && git --version
```

### Passo 3: descobrir seus IDs

```bash
id -u                            # PUID
id -g                            # PGID
getent group docker | cut -d: -f3   # DOCKER_GID
```

### Passo 4: criar as pastas e as permissões

```bash
sudo mkdir -p /srv/data/torrents/{movies,tv} /srv/data/media/{movies,tv} \
  /srv/config/{qbittorrent,prowlarr,sonarr,radarr,bazarr,jellyfin,seerr,dockhand} \
  /srv/photos/immich /srv/stacks
sudo chown -R 1000:1000 /srv/data /srv/config /srv/photos /srv/stacks
```

- Se o seu `id` **não** for `1000`, use o seu `UID:GID` no `chown`, **exceto** em `/srv/config/seerr`, que precisa ser `1000:1000` (o Seerr sempre roda como esse usuário):

  ```bash
  sudo chown -R 1000:1000 /srv/config/seerr
  ```

- Rode o `chown -R` só **antes** do primeiro `up`, com as pastas ainda vazias.

#### Disco dedicado para a mídia (opcional, recomendado)

Se `/srv/data` ficará em um HD separado, monte-o antes de criar as pastas:

```bash
lsblk -f                 # identifique o disco e copie o UUID da partição
sudo blkid               # alternativa para ver o UUID
```

Adicione uma linha ao `/etc/fstab` (troque o UUID e o sistema de arquivos pelos seus):

```
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  /srv/data  ext4  defaults,nofail  0  2
```

```bash
sudo mkdir -p /srv/data
sudo mount -a
findmnt /srv/data        # deve mostrar o disco montado
```

> Formatar um disco (`mkfs`) **apaga tudo** nele. Só faça isso em disco vazio e conferindo o dispositivo com `lsblk`.
> Deixe `torrents/` e `media/` dentro desse **mesmo** disco para os hardlinks funcionarem.

### Passo 5: clonar o repositório

O repositório é **privado**, então é preciso estar autenticado no GitHub. A senha da conta **não** funciona para `git` via HTTPS: use o GitHub CLI, um token ou uma chave SSH.

**Opção A: GitHub CLI (mais simples)**

```bash
sudo apt install -y gh
gh auth login
```

Escolha `GitHub.com` → `HTTPS` → `Login with a web browser` e responda `Yes` para autenticar o Git. Depois confirme:

```bash
gh auth status
```

**Opção B: chave SSH**

```bash
ssh-keygen -t ed25519 -C "seu-email@exemplo.com"
cat ~/.ssh/id_ed25519.pub
```

Copie a chave pública exibida em **GitHub → Settings → SSH and GPG keys → New SSH key**, e teste:

```bash
ssh -T git@github.com
```

Clone (HTTPS com a opção A, ou `git@github.com:ggabriell455/midia-server-local.git` com a opção B):

```bash
git clone https://github.com/ggabriell455/midia-server-local.git /srv/stacks
cd /srv/stacks
```

> Nunca cole tokens ou senhas em chats, issues ou arquivos versionados.

### Passo 6: criar e preencher os `.env`

```bash
cd /srv/stacks
for p in media immich dockhand; do cp "$p/.env.example" "$p/.env"; done

# UID/GID do seu usuário
sed -i "s/^PUID=.*/PUID=$(id -u)/; s/^PGID=.*/PGID=$(id -g)/" media/.env dockhand/.env

# GID do grupo docker (Dockhand)
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" dockhand/.env

# Senha do banco do Immich
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(openssl rand -hex 16)/" immich/.env
chmod 600 immich/.env
```

Revise os arquivos (`nano media/.env`, etc.) e confirme que os caminhos batem com as pastas do passo 4. Guarde o conteúdo dos `.env` em um gerenciador de senhas: eles **não** vão para o Git.

### Passo 7: validar a configuração

```bash
for p in media immich dockhand; do (cd "$p" && docker compose config -q && echo "$p: OK"); done
```

`config -q` só valida a sintaxe e as variáveis, sem subir nada. Um aviso `variable is not set` significa `.env` ausente ou incompleto.

### Passo 8: subir os serviços

```bash
for p in dockhand media immich; do (cd "/srv/stacks/$p" && docker compose up -d); done
```

Na primeira vez as imagens são baixadas (alguns GB), então pode demorar. Acompanhe:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

Todos devem aparecer como `Up`. Em caso de erro:

```bash
cd /srv/stacks/media && docker compose logs --tail 50 sonarr
```

### Passo 9: acessar os serviços

Descubra o IP do servidor:

```bash
hostname -I | awk '{print $1}'
```

| Serviço | Endereço |
|---|---|
| Jellyfin | `http://IP:8096` |
| Seerr | `http://IP:5055` |
| Sonarr | `http://IP:8989` |
| Radarr | `http://IP:7878` |
| Bazarr | `http://IP:6767` |
| Prowlarr | `http://IP:9696` |
| qBittorrent | `http://IP:8080` |
| Immich | `http://IP:2283` |
| Dockhand | `http://IP:3000` |

### Passo 10: testar o reinício

O Docker inicia sozinho com o sistema e os containers têm `restart` configurado. Confirme reiniciando o servidor:

```bash
sudo reboot
```

---

## 7. Configuração inicial de cada aplicação

Caminhos **dentro dos containers** (use exatamente estes nas telas de configuração):

| Uso | Caminho |
|---|---|
| Downloads | `/data/torrents` |
| Filmes | `/data/media/movies` |
| Séries | `/data/media/tv` |

Configure na ordem abaixo: cada etapa precisa da anterior.

### qBittorrent

1. Pegue a senha temporária (usuário `admin`):

   ```bash
   docker logs qbittorrent 2>&1 | grep -i password
   ```

2. Em **Tools → Options → WebUI**, defina uma senha própria.
3. Em **Options → Downloads**, ajuste **Default Save Path** para `/data/torrents`.

### Prowlarr

1. Crie o usuário e a senha no primeiro acesso.
2. **Indexers → Add Indexer**: cadastre os indexadores que você tem direito de usar.
3. **Settings → Apps → +**: adicione o Sonarr e o Radarr.
   - Prowlarr Server: `http://prowlarr:9696`
   - Sonarr: `http://sonarr:8989`. Radarr: `http://radarr:7878`
   - API Key: copie em cada aplicativo, em **Settings → General**.

### Sonarr

1. **Settings → Media Management → Root Folders**: adicione `/data/media/tv`.
2. Ainda em Media Management, confirme que **Use Hardlinks instead of Copy** está ligado.
3. **Settings → Download Clients → +  → qBittorrent**:
   - Host: `qbittorrent`, Port: `8080`, usuário e senha do passo anterior
   - Category: `tv`
4. Os indexadores chegam sozinhos pelo Prowlarr.

### Radarr

Igual ao Sonarr, com Root Folder `/data/media/movies` e Category `movies`.

### Bazarr

1. **Settings → Sonarr**: Host `sonarr`, Port `8989`, API Key do Sonarr. **Settings → Radarr**: Host `radarr`, Port `7878`, API Key do Radarr.
2. **Settings → Languages**: adicione *Portuguese (Brazil)*, crie um **Languages Profile** e defina-o como padrão para séries e filmes.
3. **Settings → Providers**: ative provedores de legenda (alguns exigem conta gratuita).

### Jellyfin

1. Assistente inicial: crie o usuário administrador e escolha o idioma dos metadados (Português - Brasil).
2. **Add Media Library**:
   - Tipo *Movies* → pasta `/data/media/movies`
   - Tipo *Shows* → pasta `/data/media/tv`
3. *Opcional:* transcodificação por hardware em **Dashboard → Playback → Transcoding**, depois de descomentar `devices: /dev/dri` em `media/docker-compose.yml`.

### Seerr

1. Escolha **Jellyfin** como servidor de mídia: URL `http://jellyfin:8096`, entre com sua conta do Jellyfin.
2. **Settings → Services**:
   - **Radarr**: Hostname `radarr`, Port `7878`, API Key, Root Folder `/data/media/movies`
   - **Sonarr**: Hostname `sonarr`, Port `8989`, API Key, Root Folder `/data/media/tv`
3. Convide as pessoas da casa (elas entram com a conta do Jellyfin).

### Immich

1. Abra `http://IP:2283` e crie o primeiro usuário: ele é o **administrador**.
2. Instale o app **Immich** no celular (Android/iOS), informe `http://IP:2283` como servidor e ative o **backup**.
3. Em **Administração → Configurações**, confira o backup automático do banco (padrão: diário às 2h, mantém os 14 últimos).
4. Nas primeiras horas, o servidor gera miniaturas e detecta rostos: CPU alta é normal.

### Dockhand

1. Abra `http://IP:3000` e vá em **Settings → Authentication**: **ative a autenticação e crie o administrador**. Ela vem **desativada** por padrão e o Dockhand controla o Docker do servidor.
2. Para administrar `media` e `immich` por ele, "adote" as stacks: o Dockhand as lista como *untracked*, e você informa o caminho do compose e do `.env`, por exemplo:
   - `/srv/stacks/media/docker-compose.yml` e `/srv/stacks/media/.env`
   - `/srv/stacks/immich/docker-compose.yml` e `/srv/stacks/immich/.env`

   `/srv/stacks` é montado com o mesmo caminho dentro e fora do container justamente por exigência do Dockhand ([manual](https://dockhand.pro/manual/)).

---

## 8. Operação do dia a dia

Execute dentro da pasta do projeto (`cd /srv/stacks/media`, etc.).

```bash
docker compose ps                              # estado dos containers do projeto
docker compose logs -f --tail 100 sonarr       # logs de um serviço (Ctrl+C sai)
docker compose restart sonarr                  # reinicia um serviço
docker compose stop                            # para tudo (mantém os containers)
docker compose start                           # inicia de novo
docker compose down                            # remove os containers (dados em /srv permanecem)
docker compose up -d                           # cria/atualiza conforme o compose e o .env
```

### Atualizar as aplicações

```bash
cd /srv/stacks/media
docker compose pull
docker compose up -d
docker image prune -f
```

- **Immich:** leia as *release notes* antes de atualizar. Com `IMMICH_VERSION=v3` você recebe as versões 3.x. Para trocar de versão maior, ou quando a release trouxer imagens novas do banco, substitua o compose pelo da release e compare o `.env` com o [oficial](https://docs.immich.app/install/docker-compose):

  ```bash
  cd /srv/stacks/immich
  curl -fsSL -o docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
  ```

- Faça um [backup](#9-backup) antes de atualizar o Immich.

### Diagnóstico

```bash
docker stats --no-stream                       # CPU e memória por container
docker system df                               # espaço usado pelo Docker
df -h /srv/data /srv/photos /srv/config        # espaço livre nos discos
du -sh /srv/data/media/* /srv/photos/immich    # tamanho das bibliotecas
sudo ss -tulpn | grep -E ':(8096|8989|7878|6767|9696|8080|5055|2283|3000)\b'   # portas em uso
systemctl status docker                        # estado do serviço Docker
journalctl -u docker -f                        # logs do daemon
```

### Conferir se os hardlinks estão funcionando

```bash
find /srv/data/media -type f -links +1 | head    # arquivos com mais de um link = hardlink OK
stat -c '%h links  %n' /srv/data/media/movies/*/*.mkv | head
```

`%h` maior que `1` indica que o arquivo existe também em `torrents/` sem ocupar espaço extra. Para conferir se `torrents/` e `media/` estão no mesmo disco, a coluna `Filesystem` deve ser igual:

```bash
df /srv/data/torrents /srv/data/media
```

---

## 9. Backup

| O que | Onde | Prioridade | Como |
|---|---|---|---|
| Originais do Immich | `/srv/photos/immich/library`, `upload`, `profile` | **Crítica** (insubstituível) | `rsync` para outro disco/nuvem |
| Banco do Immich | dumps em `/srv/photos/immich/backups` | **Crítica** | Automático (diário 2h, 14 últimos) + dump manual |
| Configurações dos apps | `/srv/config` (menos `immich-postgres`) | Alta | `tar` |
| Arquivos `.env` | `/srv/stacks/*/.env` | Alta | Gerenciador de senhas |
| Miniaturas e vídeos convertidos do Immich | `thumbs`, `encoded-video` | Baixa | Podem ser regenerados |
| Filmes e séries | `/srv/data/media` | Baixa | Podem ser baixados de novo |

> Não copie `/srv/config/immich-postgres` com o banco rodando: use o dump abaixo.

### Dump manual do banco do Immich

```bash
mkdir -p /srv/backups
docker exec -t immich_postgres pg_dump --clean --if-exists --dbname=immich --username=postgres | gzip > "/srv/backups/immich-db-$(date +%F).sql.gz"
```

### Backup das configurações

```bash
sudo tar --exclude=immich-postgres -czf "/srv/backups/config-$(date +%F).tar.gz" -C /srv config
```

### Copiar as fotos para um disco externo

```bash
rsync -a --info=progress2 /srv/photos/immich/ /mnt/backup/immich/
```

Siga a regra **3-2-1**: 3 cópias, em 2 tipos de mídia, com 1 fora de casa. Para restaurar o Immich, siga a [documentação oficial de backup e restauração](https://docs.immich.app/administration/backup-and-restore).

---

## 10. Acesso remoto

Não abra portas no roteador. Use uma VPN privada como o [Tailscale](https://tailscale.com/):

1. Instale no servidor (seção [5.3](#opcional-tailscale)) e rode `sudo tailscale up`.
2. Instale o app do Tailscale no celular/notebook e entre na mesma conta.
3. Descubra o IP do servidor na VPN e use no lugar do IP local:

   ```bash
   tailscale ip -4
   ```

   Exemplo: `http://100.x.y.z:2283` no app do Immich, `http://100.x.y.z:8096` no Jellyfin.

---

## 11. Segurança

- **O Docker ignora o firewall (ufw/firewalld) para portas publicadas.** Um `ufw deny 8080` **não** bloqueia uma porta publicada por container. Portanto: **não faça port-forward** no roteador e não deixe o servidor com IP público.
- **Dockhand:** ative a autenticação no primeiro acesso. Ele acessa o socket do Docker, que equivale a root.
- **Grupo `docker`:** adicione só usuários de confiança.
- **Segredos:** `.env` nunca vai para o Git (`.gitignore`). Confira com `git check-ignore -v media/.env`.
- **Senhas:** crie usuário e senha em qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr e Dockhand no primeiro acesso.
- **Privacidade nos downloads:** o qBittorrent, sem VPN, expõe o IP da sua casa aos outros peers. Se isso importa, roteie-o por um container de VPN (ex.: gluetun).
- **Atualizações:** rode o [procedimento de atualização](#atualizar-as-aplicações) periodicamente e mantenha o sistema em dia (`sudo apt update && sudo apt upgrade`).

---

## 12. Solução de problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| Seerr reinicia com `permission denied` | Pasta de configuração não pertence a `1000:1000` | `sudo chown -R 1000:1000 /srv/config/seerr` e `docker compose up -d` |
| Dockhand sem acesso ao Docker (`permission denied` no socket) | `DOCKER_GID` errado | `getent group docker \| cut -d: -f3`, corrija em `dockhand/.env` e rode `docker compose up -d` |
| `variable is not set` ao subir | `.env` ausente ou incompleto | `cp .env.example .env` e preencha |
| Postgres do Immich não sobe (senha do superusuário não definida) | `DB_PASSWORD` vazio | Preencha em `immich/.env` (veja o comando no `.env.example`) |
| Immich: `password authentication failed` | `DB_PASSWORD` foi alterada depois da primeira inicialização | Volte a senha antiga, ou altere-a dentro do banco: `docker exec -it immich_postgres psql -U postgres -c "ALTER USER postgres PASSWORD 'nova';"` |
| Container do ML do Immich não inicia | CPU sem x86-64-v2 | Confira com o comando da [seção 5.1](#51-hardware) |
| `port is already allocated` | Outra aplicação usa a porta | `sudo ss -ltnp \| grep :8080`; mude o número **à esquerda** de `porta:porta` no compose |
| Arquivos duplicados em `torrents/` e `media/` (espaço dobrado) | Hardlink não funcionou: discos diferentes | Coloque `torrents/` e `media/` no mesmo disco; confira com `df /srv/data/torrents /srv/data/media` |
| Sonarr/Radarr importam com erro de caminho | Caminhos diferentes entre os apps | Use sempre `/data/...` (veja a tabela da [seção 7](#7-configuração-inicial-de-cada-aplicação)) |
| Jellyfin não mostra a mídia | Biblioteca com caminho errado ou sem permissão de leitura | Use `/data/media/movies` e `/data/media/tv`; confira `ls -ld /srv/data/media/*` |
| Bazarr não grava legendas | Sem permissão de escrita em `/data/media` | Confira `PUID`/`PGID` e o dono das pastas (`ls -ld /srv/data/media/*`) |
| Container reiniciando em loop | Erro na aplicação | `docker compose logs --tail 100 <serviço>` |
| Um serviço falhou logo no primeiro `up` | Dependência ainda iniciando | Rode `docker compose up -d` de novo |

---

## 13. Fluxo de trabalho com Git

O repositório é a fonte da verdade: **altere os arquivos aqui, não direto nos containers.**

```bash
cd /srv/stacks
git pull --ff-only                  # traz as mudanças do repositório
cd media && docker compose up -d    # aplica no servidor
```

Para alterar algo (nova porta, novo serviço, nova versão):

```bash
cd /srv/stacks
git status
git add -A
git commit -m "media: descreva a mudança"
git push
```

Regras:

- **Nunca** versione `.env` (está no `.gitignore`); versione o `.env.example` sempre que criar ou remover uma variável.
- **Não edite** `immich/docker-compose.yml` à mão: para atualizar, use o compose da release (veja [Atualizar as aplicações](#atualizar-as-aplicações)) e ajuste tudo pelo `.env`.
- Antes de subir uma mudança, valide: `docker compose config -q` dentro da pasta do projeto.

---

## 14. Referências

- [Jellyfin](https://jellyfin.org/docs/) · [Servarr Wiki (Sonarr, Radarr, Prowlarr)](https://wiki.servarr.com/) · [Bazarr](https://wiki.bazarr.media/)
- [TRaSH Guides](https://trash-guides.info/): estrutura de pastas, hardlinks e perfis de qualidade
- [Seerr](https://docs.seerr.dev/) · [Immich](https://docs.immich.app/) · [Dockhand](https://dockhand.pro/manual/)
- [LinuxServer.io](https://docs.linuxserver.io/): imagens usadas em Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr e qBittorrent
- [Docker Engine: instalação](https://docs.docker.com/engine/install/) · [Tailscale](https://tailscale.com/kb)

---

## 15. Aviso legal

Todas as aplicações listadas são software legítimo. Use as ferramentas de download **apenas para obter conteúdo que você tem o direito de acessar**: obras próprias, de domínio público, com licença livre ou cópias que você possui legalmente. A responsabilidade pelo uso é de quem opera o servidor.
