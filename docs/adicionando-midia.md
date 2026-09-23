# Adicionando filmes e séries

[← Voltar ao README](../README.md)

O fluxo é o mesmo para filmes (Radarr) e séries (Sonarr): pedir → baixar → aparecer no Jellyfin. Pressupõe que a [configuração inicial](configuracao-inicial.md) de todos os apps já foi feita.

## 1. Peça o filme ou a série

**Pelo Radarr/Sonarr direto** (`http://IP:7878` ou `http://IP:8989`): **Add New**, busque o título, confira o **Root Folder** (`/data/media/movies` ou `/data/media/tv`) e o **Quality Profile**, e clique em **Add**. Marque **Search for Movie/Series** na hora de adicionar para já disparar a busca (ou, depois, clique no título → **Search Monitored**).

**Pelo Seerr** (`http://IP:5055`): busque o título e clique em **Request**. Ele manda o pedido para o Radarr/Sonarr sozinho — é o caminho mais simples para quem não vai mexer nos apps direto.

## 2. Acompanhe o download

Radarr/Sonarr buscam nos indexadores (via Prowlarr) → mandam o **qBittorrent** baixar → quando termina, importam o arquivo com **hardlink** para `/data/media/{movies,tv}`.

Para ver o andamento: aba **Activity → Queue** no Radarr/Sonarr, ou direto no qBittorrent (`http://IP:8080`).

## 3. Confira no Jellyfin

Normalmente o Jellyfin detecta a pasta sozinho. Se não aparecer na hora: `http://IP:8096` → **Dashboard → Libraries** → nos três pontinhos da biblioteca → **Scan Library**.

## Se travar em algum ponto

| Sintoma | Onde olhar |
|---|---|
| Busca não acha nenhum resultado | Prowlarr → **Indexers**, confira se estão ativos |
| Busca acha, mas não baixa | **Activity → Queue** no Radarr/Sonarr; confira a conexão com o qBittorrent em **Settings → Download Clients** |
| Baixa mas fica parado na fila do qBittorrent | Categoria/pasta errada — confira que a categoria (`movies`/`tv`) está indo para `/data/torrents` |
| Baixou mas não importou | **Activity → Queue**, veja a mensagem de erro (nome de arquivo não reconhecido é o mais comum) |
| Importou mas não aparece no Jellyfin | **Scan Library** manual, ou confira se a biblioteca do Jellyfin aponta para `/data/media/movies`/`/data/media/tv` |

Mais sintomas gerais (permissão, portas, hardlink) estão em [Solução de problemas](solucao-de-problemas.md).
