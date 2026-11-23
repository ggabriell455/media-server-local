# Atalhos com `make`

[← Voltar ao README](../README.md)

O [`Makefile`](../Makefile) na raiz do repositório é um **atalho**: cada alvo executa um ou mais passos do [setup manual](setup-passo-a-passo.md) e **imprime os comandos que roda** (as linhas que começam com `$`). Ele **não substitui** o passo a passo: entender cada etapa é o que permite diagnosticar problemas, e qualquer comando impresso pode ser copiado e executado à mão.

## O que ele faz e o que não faz

| Faz | Não faz |
|---|---|
| Conferir Docker, Compose v2 e o acesso ao daemon | Instalar Docker/Compose (passo 2, [seção Instalação das dependências](requisitos-e-instalacao.md#instalação-das-dependências)) |
| Criar os `.env` e preencher PUID/PGID, `DOCKER_GID` e a senha do Postgres | Clonar o repositório (passo 5): o `Makefile` já vem dentro dele |
| Criar só as pastas que faltam, com o dono certo | Configurar as aplicações pelo navegador ([seção Configuração inicial](configuracao-inicial.md)) |
| Validar os compose e as variáveis dos `.env` | Sobrescrever um `.env` que já existe |
| Subir, parar e limpar os três projetos | Mudar o dono de pastas que já existem |

## Pré-requisitos

- **GNU make**: `sudo apt install -y make`.
- **Docker Engine + Compose v2** instalados e funcionando ([seção Instalação das dependências](requisitos-e-instalacao.md#instalação-das-dependências)). O comando `docker compose version` precisa mostrar a versão 2 ou superior (`Docker Compose version 2...` ou `v2...`, conforme o pacote).
- **Repositório clonado** (passo 5), com o terminal aberto na pasta dele.
- **`sudo`** para criar pastas em `/srv`. O `make` pede a senha quando precisa. **Não rode o `make` inteiro com `sudo`**: ele recusa, porque os `.env` ficariam com `PUID=0`.

## Alvos

| Alvo | O que faz | Equivale a |
|---|---|---|
| `make` ou `make help` | Lista os alvos | |
| **`make up`** | **Tudo até ficar de pé:** roda o `setup` e sobe `dockhand`, `media` e `immich` (nessa ordem), mostrando containers e endereços | Passos 2 a 9 |
| **`make stop`** | Para todos os containers (ordem inversa). Nada é removido: `make up` os inicia de novo | |
| **`make clean`** | Remove containers, redes, volumes do Docker e imagens baixadas. **Os dados em disco e os `.env` ficam.** Pergunta `[s/N]` | |
| **`make purge`** | O `clean` **mais a remoção do conteúdo** das pastas de dados, configuração e fotos, e dos `.env`. Exige digitar uma frase | |
| `make status` | Mostra containers e endereços de acesso | Passo 9 |
| `make backup-config` | Backup das configurações dos apps em `~/backups/midia-server` (bancos SQLite copiados com segurança, sem `sudo`). Veja [Backup](operacao-backup-acesso.md#backup-das-configurações) | |
| `make check` | Confere Docker, Compose v2 e o daemon (não instala nada) | Passo 2 (só a conferência) |
| `make env` | Cria e preenche os `.env` e cria os `docker-compose.override.yml` a partir dos exemplos | Passos 3 e 6 |
| `make dirs` | Cria as pastas de dados e configuração | Passo 4 |
| `make validate` | Valida os compose e as variáveis dos `.env` | Passo 7 |
| `make setup` | `check` + `env` + `dirs` + `validate`, **sem subir nada** | Passos 2 a 7 |

Os alvos encadeiam o que precisam: `make dirs` roda `make env` antes, e `make up` roda `make setup` antes.

## Fluxos típicos

**Primeira instalação** (Docker instalado e repositório clonado):

```bash
make up
```

**Parar para manutenção e voltar depois** (nada é apagado):

```bash
make stop
```

```bash
make up
```

**Reinstalar do zero mantendo os dados** (as imagens são baixadas de novo):

```bash
make clean
```

```bash
make up
```

**Recomeçar 100% do zero** (apaga tudo, inclusive fotos e configurações; faça [backup](operacao-backup-acesso.md#backup) antes):

```bash
make purge
```

```bash
make up
```

## Como cada alvo se comporta

- **`make env`:** cria cada `.env` a partir do `.env.example` **apenas se ele não existir**. Nos arquivos novos, define `PUID`/`PGID` com o seu `id -u`/`id -g` e `DOCKER_GID` com o grupo dono do socket `/var/run/docker.sock` (ou, se não houver socket, o do grupo `docker`). A `DB_PASSWORD` do Immich é gerada **somente se estiver vazia**: uma senha existente nunca é sobrescrita, porque trocá-la depois que o banco foi criado o deixa inacessível. Os `.env` ficam com permissão `600`. Também cria `media/docker-compose.override.yml` e `immich/docker-compose.override.yml` a partir dos `docker-compose.override.example.yml` **apenas se eles não existirem**: o padrão traz só o que vale para qualquer servidor (rotação de logs, política de reinício); a aceleração por GPU e o IP ficam **comentados** para você descomentar conforme o seu hardware ([Hardware e ajustes desta máquina](hardware-desta-maquina.md)).
- **`make dirs`:** cria **somente as pastas que faltam**, incluindo a do banco do Immich, e nunca altera o dono nem o conteúdo de pastas que já existem. Usa `sudo install -d` quando o local não é gravável por você (como `/srv`). A pasta do Seerr é sempre `1000:1000`. Avisa se `torrents/` e `media/` estiverem em discos diferentes (sem hardlinks, o espaço dobra).
- **`make up`:** pode ser repetido à vontade, pois só cria o que falta. Se um projeto falhar, os outros continuam a subir e, no fim, o `make` lista quais falharam. Para investigar, use o [passo a passo](setup-passo-a-passo.md) e os logs: `cd <projeto> && docker compose logs`.
- **`make stop`:** usa `docker compose stop`. Containers, imagens, volumes e dados continuam onde estão.
- **`make clean`:** usa `docker compose down --remove-orphans --volumes --rmi all` em cada projeto. Remove os **volumes do Docker** e as **imagens**, não os dados em disco (`/srv/...`).

## Proteções do `make purge`

O `purge` é o único alvo que apaga dados, por isso é o mais restrito:

- **Confirmação digitada:** é preciso escrever `APAGAR TUDO`. Não existe atalho como o `YES=1` do `clean`, e sem terminal interativo ele recusa.
- **Mostra antes** cada pasta que será esvaziada, com o tamanho, e os `.env` que serão removidos.
- **Recusa caminhos perigosos** vindos dos `.env`: relativos, com `..`, a raiz `/`, pastas de primeiro nível (como `/srv`), diretórios do sistema (`/etc`, `/usr`, `/bin`, `/boot`, `/dev`, `/proc`, `/root`, `/run`, `/sys`, `/sbin`, `/lib`), a sua pasta pessoal inteira (`/home/usuario`) e **a pasta do repositório ou qualquer pasta que a contenha**. Por isso use subpastas dedicadas, como `/srv/data`.
- **Só esvazia:** as pastas (que podem ser pontos de montagem de discos) continuam existindo, vazias. Não atravessa outros discos montados dentro delas (`-xdev`).
- **Nunca toca no repositório** nem em nada fora das pastas listadas.

## Dicas

- `make -n up` mostra o que seria executado, sem rodar nada.
- Rodar de outra pasta: `make -C /srv/stacks up`.
- `make clean YES=1` pula a pergunta `[s/N]` (útil em scripts). O `purge` não tem equivalente.
- Para usar outras pastas de dados, edite os `.env` **antes** do primeiro `make dirs`.
