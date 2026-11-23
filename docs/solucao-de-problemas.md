# Solução de problemas e segurança

[← Voltar ao README](../README.md)

## Solução de problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| Seerr reinicia com `permission denied` | Pasta de configuração não pertence a `1000:1000` | `sudo chown -R 1000:1000 /srv/config/seerr` e `docker compose up -d` |
| Dockhand sem acesso ao Docker (`permission denied` no socket) | `DOCKER_GID` errado | `getent group docker \| cut -d: -f3`, corrija em `dockhand/.env` e rode `docker compose up -d` |
| `variable is not set` ao subir | `.env` ausente ou incompleto | `cp .env.example .env` e preencha |
| Postgres do Immich não sobe (senha do superusuário não definida) | `DB_PASSWORD` vazio | Preencha em `immich/.env` (veja o comando no `.env.example`) |
| Immich: `password authentication failed` | `DB_PASSWORD` foi alterada depois da primeira inicialização | Volte a senha antiga, ou altere-a dentro do banco: `docker exec -it immich_postgres psql -U postgres -c "ALTER USER postgres PASSWORD 'nova';"` |
| Container do ML do Immich não inicia | CPU sem x86-64-v2 | Confira com o comando da [seção Hardware](requisitos-e-instalacao.md#hardware) |
| `port is already allocated` | Outra aplicação usa a porta | `sudo ss -ltnp \| grep :8080`; mude o número **à esquerda** de `porta:porta` no compose |
| Arquivos duplicados em `torrents/` e `media/` (espaço dobrado) | Hardlink não funcionou: discos diferentes | Coloque `torrents/` e `media/` no mesmo disco; confira com `df /srv/data/torrents /srv/data/media` |
| Sonarr/Radarr importam com erro de caminho | Caminhos diferentes entre os apps | Use sempre `/data/...` (veja a tabela da [seção Configuração inicial](configuracao-inicial.md)) |
| Jellyfin não mostra a mídia | Biblioteca com caminho errado ou sem permissão de leitura | Use `/data/media/movies` e `/data/media/tv`; confira `ls -ld /srv/data/media/*` |
| Episódios ou filmes aparecem trocados ou repetidos no Jellyfin (por exemplo, três arquivos como o mesmo episódio) | O renomeio está desligado e o nome do release tem vários números (o "10" de `HEVC-10bit` vira o episódio 10) | Ligue **Rename Episodes** no Sonarr e **Rename Movies** no Radarr ([Configuração inicial](configuracao-inicial.md#sonarr)) e use **Preview Rename** nos itens já importados |
| Série ou filme novo só aparece no Jellyfin depois de escanear | O Jellyfin só passa a vigiar uma pasta depois de um scan que encontre conteúdo nela, e o aviso do Sonarr/Radarr não basta para um título novo | Rode uma vez **Painel → Bibliotecas → Escanear todas as bibliotecas**; depois a pasta passa a ser vigiada. Opcional: em **Tarefas agendadas → Escanear a Biblioteca de Mídia**, adicione um gatilho de 1 hora |
| Bazarr não grava legendas | Sem permissão de escrita em `/data/media` | Confira `PUID`/`PGID` e o dono das pastas (`ls -ld /srv/data/media/*`) |
| Container reiniciando em loop | Erro na aplicação | `docker compose logs --tail 100 <serviço>` |
| Um serviço falhou logo no primeiro `up` | Dependência ainda iniciando | Rode `docker compose up -d` de novo |
| `make` para com "Precisa do Docker Compose v2" | O comando `docker compose` não existe ou é uma versão antiga | Instale o plugin Compose v2 ([seção Instalação das dependências](requisitos-e-instalacao.md#instalação-das-dependências)) e confira que `docker compose version` mostra a versão 2 ou superior |
| `make` para com "Sem acesso ao daemon do Docker" | Daemon parado ou seu usuário sem permissão | `sudo systemctl enable --now docker`; `sudo usermod -aG docker $USER` e abra uma nova sessão |
| `make` para com "Não rode o make como root" | Foi executado com `sudo make` | Rode como usuário comum: o `make` usa `sudo` sozinho quando precisa |
| Falha ao criar pastas em `/srv` | Seu usuário não tem `sudo` | Peça a um administrador para criar as pastas (passo 4) ou aponte os `.env` para pastas na sua home |
| `make purge` diz "Caminho recusado por segurança" | Um caminho dos `.env` é perigoso (ex.: `/srv`, `/home/usuario` ou a pasta do repositório) | Use subpastas dedicadas, como `/srv/data` (veja [Proteções do `make purge`](atalhos-make.md#proteções-do-make-purge)) |

## Segurança

- **O Docker ignora o firewall (ufw/firewalld) para portas publicadas.** Um `ufw deny 8080` **não** bloqueia uma porta publicada por container. Portanto: **não faça port-forward** no roteador e não deixe o servidor com IP público.
- **Dockhand:** ative a autenticação no primeiro acesso. Ele acessa o socket do Docker, que equivale a root.
- **Grupo `docker`:** adicione só usuários de confiança.
- **Segredos:** `.env` nunca vai para o Git (`.gitignore`). Confira com `git check-ignore -v media/.env`.
- **Senhas:** crie usuário e senha em qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr e Dockhand no primeiro acesso.
- **Privacidade nos downloads:** o qBittorrent, sem VPN, expõe o IP da sua casa aos outros peers. Se isso importa, roteie-o por um container de VPN (ex.: gluetun).
- **Atualizações:** rode o [procedimento de atualização](operacao-backup-acesso.md#atualizar-as-aplicações) periodicamente e mantenha o sistema em dia (`sudo apt update && sudo apt upgrade`).
