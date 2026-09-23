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

## Prowlarr

1. Crie o usuário e a senha no primeiro acesso.
2. **Indexers → Add Indexer**: cadastre os indexadores que você tem direito de usar.
3. **Settings → Apps → +**: adicione o Sonarr e o Radarr.
   - Prowlarr Server: `http://prowlarr:9696`
   - Sonarr: `http://sonarr:8989`. Radarr: `http://radarr:7878`
   - API Key: copie em cada aplicativo, em **Settings → General**.

## Sonarr

1. **Settings → Media Management → Root Folders**: adicione `/data/media/tv`.
2. No topo da mesma tela, clique em **Show Advanced** (fica escondido por padrão). Em **File Management**, confirme que **Use Hardlinks instead of Copy** está ligado.
3. **Settings → Download Clients → +  → qBittorrent**:
   - Host: `qbittorrent`, Port: `8080`, usuário e senha do passo anterior
   - Category: `tv`
4. Os indexadores chegam sozinhos pelo Prowlarr.

## Radarr

Igual ao Sonarr, com Root Folder `/data/media/movies` e Category `movies`.

## Bazarr

1. **Settings → Library → aba Sonarr**: ative o toggle **Enabled** primeiro — os campos de conexão só aparecem depois disso. Preencha Address/Host `sonarr`, Port `8989`, API Key do Sonarr. Repita na aba **Radarr**: Host `radarr`, Port `7878`, API Key do Radarr.
2. **Settings → Languages**: adicione *Portuguese (Brazil)*, crie um **Languages Profile** e defina-o como padrão para séries e filmes.
3. **Settings → Providers**: ative provedores de legenda (alguns exigem conta gratuita).

## Jellyfin

1. Assistente inicial: crie o usuário administrador e escolha o idioma dos metadados (Português - Brasil).
2. **Add Media Library**:
   - Tipo *Movies* → pasta `/data/media/movies`
   - Tipo *Shows* → pasta `/data/media/tv`
3. *Opcional:* transcodificação por hardware em **Dashboard → Playback → Transcoding**, depois de descomentar `devices: /dev/dri` em `media/docker-compose.yml`.

## Seerr

1. Escolha **Jellyfin** como servidor de mídia: URL `http://jellyfin:8096`, entre com sua conta do Jellyfin.
2. **Settings → Services**:
   - **Radarr**: Hostname `radarr`, Port `7878`, API Key, Root Folder `/data/media/movies`
   - **Sonarr**: Hostname `sonarr`, Port `8989`, API Key, Root Folder `/data/media/tv`
3. Convide as pessoas da casa (elas entram com a conta do Jellyfin).

## Immich

1. Abra `http://IP:2283` e crie o primeiro usuário: ele é o **administrador**.
2. Instale o app **Immich** no celular (Android/iOS), informe `http://IP:2283` como servidor e ative o **backup**.
3. Em **Administração → Configurações**, confira o backup automático do banco (padrão: diário às 2h, mantém os 14 últimos).
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
