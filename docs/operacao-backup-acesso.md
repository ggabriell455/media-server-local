# Operação, backup e acesso remoto

[← Voltar ao README](../README.md)

## Operação do dia a dia

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

- Faça um [backup](#backup) antes de atualizar o Immich.

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

## Backup

| O que | Onde | Prioridade | Como |
|---|---|---|---|
| Originais do Immich | `/srv/photos/immich/library`, `upload`, `profile` | **Crítica** (insubstituível) | `rsync` para outro disco/nuvem |
| Banco do Immich | dumps em `/srv/photos/immich/backups` | **Crítica** | Automático (diário 2h, 14 últimos) + dump manual |
| Configurações dos apps | `/srv/config` (menos `immich-postgres`) | Alta | `make backup-config` (script) |
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

O script [`scripts/backup-config.py`](../scripts/backup-config.py) gera um `.tar.gz` datado em `~/backups/midia-server` com as configurações de todos os apps e os `.env`/compose. Ele **não precisa de `sudo`** e copia os bancos SQLite com a API de backup do SQLite, que dá uma cópia consistente com o app rodando (um `tar` simples pode pegar o banco no meio de uma gravação). Ignora caches, logs e o banco do Immich (para ele use o dump acima) e mantém os 14 últimos.

```bash
make backup-config
```

Para agendar todo dia às 4h30, rode `crontab -e` e acrescente (troque o caminho pelo do seu clone):

```cron
30 4 * * * /usr/bin/python3 /caminho/do/repo/scripts/backup-config.py >> ~/backups/midia-server/backup.log 2>&1
```

Como o backup fica no mesmo disco, defina `BACKUP_SECOND_DEST=/caminho` (HD externo ou pasta de rede) no comando ou no crontab para gravar uma segunda cópia. Para restaurar, pare os containers (`make stop`), extraia o arquivo e copie a pasta `config/` de volta para `/srv/config`.

O `tar` manual continua valendo, se preferir:

```bash
sudo tar --exclude=immich-postgres -czf "/srv/backups/config-$(date +%F).tar.gz" -C /srv config
```

### Copiar as fotos para um disco externo

```bash
rsync -a --info=progress2 /srv/photos/immich/ /mnt/backup/immich/
```

Siga a regra **3-2-1**: 3 cópias, em 2 tipos de mídia, com 1 fora de casa. Para restaurar o Immich, siga a [documentação oficial de backup e restauração](https://docs.immich.app/administration/backup-and-restore).

## Acesso remoto

Não abra portas no roteador. Use uma VPN privada como o [Tailscale](https://tailscale.com/):

1. Instale no servidor (seção [5.3](requisitos-e-instalacao.md#opcional-tailscale)) e rode `sudo tailscale up`.
2. Instale o app do Tailscale no celular/notebook e entre na mesma conta.
3. Descubra o IP do servidor na VPN e use no lugar do IP local:

   ```bash
   tailscale ip -4
   ```

   Exemplo: `http://100.x.y.z:2283` no app do Immich, `http://100.x.y.z:8096` no Jellyfin.

## Fluxo de trabalho com Git

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
- Antes de subir uma mudança, valide: `make validate` (ou `docker compose config -q` dentro da pasta do projeto).
