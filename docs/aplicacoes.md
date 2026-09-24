# Aplicações

[← Voltar ao README](../README.md)

> A tabela-resumo (finalidade, porta e projeto de cada aplicação) e o diagrama de como tudo se conecta estão no [README](../README.md#aplicações).

## Jellyfin

- **O que é:** servidor de mídia open source e gratuito, alternativa ao Plex e ao Emby. Sem conta obrigatória e sem telemetria.
- **Para que serve:** organiza sua biblioteca com capas, sinopses, elenco e legendas, e transmite para TV, celular, navegador, etc. Converte (transcodifica) o vídeo quando o dispositivo não suporta o formato original.
- **Papel no ecossistema:** só **reproduz**. Quem traz os arquivos para a pasta é o Radarr/Sonarr. A pasta de mídia é montada como **somente leitura** (`:ro`), então o Jellyfin não consegue apagar seus arquivos.
- **Dados:** configuração em `/srv/config/jellyfin`; mídia em `/srv/data/media`.

## Radarr

- **O que é:** gerenciador automático de **filmes**.
- **Para que serve:** você adiciona um filme à lista. O Radarr procura nos indexadores, manda o cliente de torrent baixar, **renomeia** e **move (via hardlink)** o arquivo para `/data/media/movies`. Também troca por versões de melhor qualidade quando aparecem.
- **Depende de:** Prowlarr (busca), qBittorrent (download).

## Sonarr

- **O que é:** o equivalente do Radarr para **séries**.
- **Para que serve:** acompanha as séries que você segue, detecta episódios novos, baixa, renomeia e organiza em `/data/media/tv` (uma pasta por série/temporada).
- **Depende de:** Prowlarr, qBittorrent.

## Bazarr

- **O que é:** gerenciador de **legendas**, companheiro do Sonarr e do Radarr.
- **Para que serve:** lê as bibliotecas do Sonarr/Radarr, descobre o que está sem legenda no idioma desejado (ex.: português do Brasil) e baixa de provedores de legenda. Salva ao lado do vídeo, onde o Jellyfin encontra.
- **Depende de:** Sonarr e Radarr. Precisa de escrita em `/data/media`.

## Prowlarr

- **O que é:** gerenciador central de **indexadores** (os sites/trackers onde a busca é feita).
- **Para que serve:** você cadastra os indexadores **uma vez** no Prowlarr, e ele os sincroniza automaticamente com Sonarr e Radarr. Sem ele, seria preciso cadastrar cada indexador em cada aplicativo.

## FlareSolverr

- **O que é:** um proxy que resolve o desafio anti-robô do Cloudflare (o "Verificando se você é humano...") rodando um navegador de verdade (Chromium) por trás dos panos.
- **Para que serve:** alguns indexadores ficam atrás do Cloudflare, e o Prowlarr sozinho, fazendo requisições HTTP simples, não passa por esse desafio — a busca falha ou volta vazia. O FlareSolverr resolve o desafio, pega os cookies de sessão válidos e devolve para o Prowlarr usar.
- **Opcional:** só é necessário se algum indexador específico exigir (o Prowlarr avisa, ou a busca falha com erro de Cloudflare). Cadastro em [Configuração inicial](configuracao-inicial.md#prowlarr).
- **Depende de:** nada; é usado pelo Prowlarr, não o contrário.
- **Acesso:** não publica porta no servidor (não há `http://IP:8191`): só o Prowlarr o alcança, pela rede interna do Docker (`http://flaresolverr:8191`). O estado dele aparece como *healthy* em `docker ps`.

## qBittorrent

- **O que é:** cliente de torrent com interface web.
- **Para que serve:** executa os downloads pedidos pelo Sonarr/Radarr, salvando em `/data/torrents`. Não gerencia a biblioteca final.
- **Portas:** `8080` (interface web) e `6881` TCP/UDP (conexão com outros peers).

## Seerr

- **O que é:** interface de **pedidos** para você e a família. É o sucessor unificado do Jellyseerr e do Overseerr.
- **Para que serve:** as pessoas entram com a conta do Jellyfin, procuram um filme ou série e clicam em "pedir". O Seerr envia o pedido ao Radarr/Sonarr, que cuidam do resto.
- **Depende de:** Jellyfin (login e biblioteca), Sonarr e Radarr. Roda como usuário `1000:1000` dentro do container.

## Immich

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

## Dockhand

- **O que é:** interface web para administrar o Docker (na linha do Portainer).
- **Para que serve:** ver containers, logs e uso de recursos, abrir terminal, reiniciar serviços e editar stacks Compose, tudo pelo navegador.
- **Papel neste repositório:** conveniência. A fonte da verdade continua sendo o Git + `docker compose`.
- **Cuidado:** ele acessa o socket do Docker (equivale a **root** no servidor). Ative a autenticação assim que subir ([seção Dockhand da configuração inicial](configuracao-inicial.md#dockhand)).

## Dependências entre os serviços

Ordem em que o Compose sobe os containers (`depends_on`):

| Serviço | Depende de |
|---|---|
| Sonarr, Radarr | qBittorrent, Prowlarr |
| Bazarr | Sonarr, Radarr |
| Seerr | Jellyfin, Sonarr, Radarr |
| immich-server | redis, database |

`depends_on` só controla a **ordem de início**, não garante que o outro serviço já esteja pronto. Se algo falhar logo no primeiro `up`, rode `docker compose up -d` de novo.

Os containers do mesmo projeto se enxergam pelo **nome do container**. Por isso, na configuração, use `http://sonarr:8989` em vez do IP do servidor.

## Por que existe uma única pasta `/data` (hardlinks)

Sonarr e Radarr montam a raiz `/data` **inteira**, com `torrents/` e `media/` lado a lado. Assim, ao "importar", eles criam um **hardlink**: o mesmo arquivo aparece nas duas pastas **sem ocupar espaço duas vezes**, e o torrent continua semeando. Isso só funciona se `torrents/` e `media/` estiverem **no mesmo disco/partição**. Se você usar discos separados, os arquivos são copiados e o espaço dobra.
