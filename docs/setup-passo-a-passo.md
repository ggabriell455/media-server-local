# Setup passo a passo

[← Voltar ao README](../README.md)

Este é o processo manual completo. O [`Makefile`](../Makefile) automatiza estes passos como atalho (veja [Atalhos com `make`](atalhos-make.md)).

## Antes de começar: pastas e variáveis

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

## Passo 1: conferir a máquina

```bash
cat /etc/os-release      # distribuição e versão
uname -m                 # arquitetura (esperado: x86_64)
nproc                    # núcleos de CPU
free -h                  # memória
lsblk -f                 # discos, partições e sistemas de arquivos
df -h                    # espaço livre
```

## Passo 2: instalar as dependências

> **Atalho:** depois de instalar, `make check` confere Docker, Compose v2 e o acesso ao daemon (não instala nada). Veja a [seção Atalhos com `make`](atalhos-make.md).

Siga a [seção Instalação das dependências](requisitos-e-instalacao.md#instalação-das-dependências) e confirme:

```bash
docker --version && docker compose version && git --version
```

## Passo 3: descobrir seus IDs

> **Atalho:** o `make env` descobre esses valores e já os grava nos `.env` (passo 6).

```bash
id -u                            # PUID
id -g                            # PGID
getent group docker | cut -d: -f3   # DOCKER_GID
```

## Passo 4: criar as pastas e as permissões

> **Atalho:** `make dirs` cria só as pastas que faltam, com o dono certo, usando `sudo` quando precisa.

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

### Disco dedicado para a mídia (opcional, recomendado)

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

## Passo 5: clonar o repositório

O repositório é **privado**, então é preciso estar autenticado no GitHub. A senha da conta **não** funciona para `git` via HTTPS: use o GitHub CLI, um token ou uma chave SSH.

**Opção A: GitHub CLI (mais simples, e a única que sempre funciona independente do protocolo escolhido)**

```bash
sudo apt install -y gh
gh auth login
```

Escolha `GitHub.com`, depois `HTTPS` **ou** `SSH` (tanto faz), e `Login with a web browser`. Confirme com `gh auth status` e clone com o próprio `gh`, que descobre sozinho o protocolo certo:

```bash
gh repo clone ggabriell455/midia-server-local /srv/stacks
cd /srv/stacks
```

> Se você escolheu `SSH` no `gh auth login` (confira em `gh auth status`, campo "Git operations protocol"), um `git clone https://...` normal **falha** com `could not read Username for 'https://github.com'` — use sempre `gh repo clone` nesse caso, ou clone pelo endereço SSH da opção B.

**Opção B: chave SSH**

```bash
ssh-keygen -t ed25519 -C "seu-email@exemplo.com"
cat ~/.ssh/id_ed25519.pub
```

Copie a chave pública exibida em **GitHub → Settings → SSH and GPG keys → New SSH key**, teste e clone:

```bash
ssh -T git@github.com
git clone git@github.com:ggabriell455/midia-server-local.git /srv/stacks
cd /srv/stacks
```

> Nunca cole tokens ou senhas em chats, issues ou arquivos versionados.

## Passo 6: criar e preencher os `.env`

> **Atalho:** `make env`. Nunca sobrescreve um `.env` que já existe.

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

## Passo 7: validar a configuração

> **Atalho:** `make validate`.

```bash
for p in media immich dockhand; do (cd "$p" && docker compose config -q && echo "$p: OK"); done
```

`config -q` só valida a sintaxe e as variáveis, sem subir nada. Um aviso `variable is not set` significa `.env` ausente ou incompleto.

## Passo 8: subir os serviços

> **Atalho:** `make up` faz os passos 2 a 8 e mostra os endereços do passo 9. `make stop` para tudo.

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

## Passo 9: acessar os serviços

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
| FlareSolverr | `http://IP:8191` (sem interface, só um JSON de status) |
| qBittorrent | `http://IP:8080` |
| Immich | `http://IP:2283` |
| Dockhand | `http://IP:3000` |

## Passo 10: testar o reinício

O Docker inicia sozinho com o sistema e os containers têm `restart` configurado. Confirme reiniciando o servidor:

```bash
sudo reboot
```
