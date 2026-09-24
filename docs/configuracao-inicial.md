# Configuração inicial de cada aplicação

[← Voltar ao README](../README.md)

Caminhos **dentro dos containers** (use exatamente estes nas telas de configuração):

| Uso | Caminho |
|---|---|
| Downloads | `/data/torrents` |
| Filmes | `/data/media/movies` |
| Séries | `/data/media/tv` |

Configure na ordem abaixo: cada etapa precisa da anterior.

## qBittorrent

1. Pegue a senha temporária (usuário `admin`):

   ```bash
   docker logs qbittorrent 2>&1 | grep -i password
   ```

2. Em **Tools → Options → WebUI**, defina uma senha própria.
3. Em **Options → Downloads**, ajuste **Default Save Path** para `/data/torrents`.
4. Crie as categorias que o Sonarr e o Radarr vão usar, cada uma com o **Save Path** apontando para a subpasta certa (senão tudo cai solto direto em `/data/torrents`, sem separar filme de série): clique com o botão direito em **Categories** (barra lateral esquerda) → **Add category**.
   - `tv` → Save Path `/data/torrents/tv`
   - `movies` → Save Path `/data/torrents/movies`

## Sonarr

1. **Settings → Media Management → Root Folders**: adicione `/data/media/tv`.
2. No topo da mesma tela, clique em **Show Advanced** (fica escondido por padrão). Em **File Management**, confirme que **Use Hardlinks instead of Copy** está ligado.
3. **Settings → Download Clients → +  → qBittorrent**:
   - Host: `qbittorrent`, Port: `8080`, usuário e senha do passo anterior
   - Category: `tv` (a categoria criada no qBittorrent)
4. *Opcional:* **Settings → Profiles** — os perfis padrão de qualidade/idioma vêm em inglês. Ajuste ou crie um perfil conforme sua preferência; o [TRaSH Guides](https://trash-guides.info/) (já citado nas [Referências](../README.md#referências)) tem recomendações prontas para copiar.
5. Os indexadores chegam sozinhos pelo Prowlarr (próximo passo).

## Radarr

Igual ao Sonarr, com Root Folder `/data/media/movies` e Category `movies`.

## Prowlarr

1. Crie o usuário e a senha no primeiro acesso.
2. **Indexers → Add Indexer**: cadastre os indexadores que você tem direito de usar.
3. **Settings → Apps → +**: adicione o Sonarr e o Radarr.
   - Prowlarr Server: `http://prowlarr:9696`
   - Sonarr: `http://sonarr:8989`. Radarr: `http://radarr:7878`
   - API Key: copie em cada aplicativo, em **Settings → General** (ela já existe desde que o container subiu, mesmo que você não tenha terminado de configurar o app ainda).
   - Sync Level: deixe **Full Sync** (o padrão) — mantém os indexadores sincronizados automaticamente.
4. *Opcional, só se algum indexador exigir* (aviso de saúde no Prowlarr, ou busca falhando com erro de Cloudflare): **Settings → Indexer Proxies → +  → FlareSolverr**.
   - Host: `http://flaresolverr:8191`
   - Tags: crie uma tag, por exemplo `flaresolverr`
   - Depois, no indexador que precisa (**Indexers → editar o indexador**), adicione essa mesma tag no campo **Tags** lá embaixo. Sem a tag em comum nos dois lados, o proxy não é usado.

## Bazarr

1. **Settings → Library → aba Sonarr**: ative o toggle **Enabled** primeiro — os campos de conexão só aparecem depois disso. Preencha Address/Host `sonarr`, Port `8989`, API Key do Sonarr. Repita na aba **Radarr**: Host `radarr`, Port `7878`, API Key do Radarr.
2. **Settings → Languages**: adicione *Portuguese (Brazil)*, crie um **Languages Profile** e defina-o como padrão para séries e filmes.
3. **Settings → Providers**: ative provedores de legenda (alguns exigem conta gratuita).

## Jellyfin

1. Assistente inicial: crie o usuário administrador e escolha o idioma dos metadados (Português - Brasil).
2. **Adicione as duas bibliotecas** (ícone de usuário → **Painel administrativo** → **Bibliotecas** → **Adicionar biblioteca de mídia**, uma vez para cada):
   - Tipo *Filmes* (Movies) → pasta `/data/media/movies`
   - Tipo *Séries* (Shows) → pasta `/data/media/tv`

   As duas pastas são as do **container**, não as do seu servidor. Esqueceu uma? Ela não aparece na tela inicial — repita o passo acima só para a que falta.
3. *Opcional:* transcodificação por hardware em **Dashboard → Playback → Transcoding**, depois de repassar a GPU ao container. O jeito mais limpo é criar `media/docker-compose.override.yml` (o Git o ignora e o Compose o aplica sozinho) em vez de editar o `docker-compose.yml`:

   ```yaml
   services:
     jellyfin:
       devices:
         - /dev/dri/renderD128:/dev/dri/renderD128   # confira o seu com: ls -l /dev/dri/by-path
       group_add:
         - "992"   # GID do grupo "render": getent group render
   ```

   Depois rode `docker compose up -d` em `media/` e escolha **VAAPI** (ou **Intel QuickSync**) no painel. Dá para testar antes de confiar: `docker exec -u abc jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -init_hw_device vaapi=va:/dev/dri/renderD128 -f lavfi -i testsrc=duration=1 -vf format=nv12,hwupload -c:v h264_vaapi -f null -` deve terminar sem erro.

## Seerr

1. Escolha **Jellyfin** como servidor de mídia: URL `http://jellyfin:8096`, entre com sua conta do Jellyfin.
2. **Settings → Services**:
   - **Radarr**: Hostname `radarr`, Port `7878`, API Key (a mesma copiada em **Settings → General** do Radarr), Root Folder `/data/media/movies`
   - **Sonarr**: Hostname `sonarr`, Port `8989`, API Key (idem, do Sonarr), Root Folder `/data/media/tv`
3. Convide as pessoas da casa (elas entram com a conta do Jellyfin).

Com tudo configurado, o fluxo de pedir um filme ou série até ele aparecer no Jellyfin está em [Adicionando filmes e séries](adicionando-midia.md).

## Immich

1. Abra `http://IP:2283` e crie o primeiro usuário: ele é o **administrador**.
2. Instale o app **Immich** no celular (Android/iOS), informe `http://IP:2283` como servidor e ative o **backup**.
3. Em **Administration → Settings → Backup** (menu do administrador; pode aparecer traduzido dependendo do idioma da sua conta), confira o backup automático do banco (padrão: diário às 2h, mantém os 14 últimos).
4. Nas primeiras horas, o servidor gera miniaturas e detecta rostos: CPU alta é normal.

## Dockhand

1. Abra `http://IP:3000` e vá em **Settings → Authentication**: **ative a autenticação e crie o administrador**. Ela vem **desativada** por padrão e o Dockhand controla o Docker do servidor.
2. **Settings → Environments**: o Dockhand não detecta o Docker do próprio host sozinho — sem cadastrar isso, nenhuma tela mostra container nenhum ("No environments" no topo, tabela vazia). Clique em **Add environment**:
   - **Name:** por exemplo `local`
   - **Connection type:** `Unix socket` (a lista também mostra *Direct connection*, *Hawser agent (standard)* e *Hawser agent (edge)* — são para Docker remoto/outra máquina; aqui é tudo no mesmo host, então é sempre *Unix socket*)
   - **Socket path:** já vem preenchido com `/var/run/docker.sock` — é o socket montado em [dockhand/docker-compose.yml](../dockhand/docker-compose.yml), não precisa alterar
   - **Public IP:** deixe em branco (opcional, só afeta links de porta)

   Clique em **Test connection** e depois em **Add**.
3. Para administrar `media` e `immich` por ele, "adote" as stacks: o Dockhand as lista como *untracked*, e você informa o caminho do compose e do `.env`, por exemplo:
   - `/srv/stacks/media/docker-compose.yml` e `/srv/stacks/media/.env`
   - `/srv/stacks/immich/docker-compose.yml` e `/srv/stacks/immich/.env`

   `/srv/stacks` é montado com o mesmo caminho dentro e fora do container justamente por exigência do Dockhand ([manual](https://dockhand.pro/manual/)).
