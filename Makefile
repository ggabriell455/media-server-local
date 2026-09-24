# ==============================================================================
# midia-server-local: atalhos para o setup
#
# É um ATALHO, não um substituto do passo a passo (docs/setup-passo-a-passo.md):
# cada alvo executa um ou mais passos manuais e mostra os comandos que roda.
# Detalhes em docs/atalhos-make.md.
#
#   make          lista os alvos
#   make up       faz tudo até deixar tudo de pé
#   make stop     para tudo (nada é removido)
#   make clean    remove containers, redes, volumes e imagens (os dados ficam)
#   make purge    clean + APAGA os dados e os .env (pede confirmação digitada)
#
# Requer GNU make, `docker` e `docker compose` (v2).
# ==============================================================================

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.ONESHELL:
.SILENT:
.NOTPARALLEL:
.DEFAULT_GOAL := help

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECTS  := dockhand media immich
RPROJECTS := immich media dockhand
URLS      := Jellyfin:8096 Seerr:5055 Sonarr:8989 Radarr:7878 Bazarr:6767 Prowlarr:9696 qBittorrent:8080 Immich:2283 Dockhand:3000

# Funções de shell compartilhadas. Cada alvo começa com $(LIB); como o Makefile
# usa .ONESHELL, tudo roda em um único shell (bash) por alvo.
define LIB
ROOT="$(ROOT)"
cd "$$ROOT"
projects="$(PROJECTS)"
rprojects="$(RPROJECTS)"
if [ -t 1 ]; then B=$$'\033[1m'; G=$$'\033[32m'; Y=$$'\033[33m'; R=$$'\033[31m'; D=$$'\033[2m'; Z=$$'\033[0m'; else B=; G=; Y=; R=; D=; Z=; fi
if [ "$$(id -u)" -eq 0 ]; then S=; else S=sudo; fi
say()  { printf '%s==>%s %s\n' "$$B" "$$Z" "$$*"; }
ok()   { printf ' %s✓%s %s\n' "$$G" "$$Z" "$$*"; }
warn() { printf ' %s!%s %s\n' "$$Y" "$$Z" "$$*" >&2; }
die()  { printf ' %s✗%s %s\n' "$$R" "$$Z" "$$*" >&2; exit 1; }
run()  { printf '%s$$' "$$D"; for a in "$$@"; do case "$$a" in *[[:space:]]*) printf " '%s'" "$$a";; *) printf ' %s' "$$a";; esac; done; printf '%s\n' "$$Z"; "$$@"; }
envval() { sed -n "s/^$$2=//p" "$$1/.env" 2>/dev/null | tail -n1 || true; }
setval() { sed -i "s|^$$2=.*|$$2=$$3|" "$$1/.env"; }
confirm() {
  [ "$(YES)" = "1" ] && return 0
  [ -t 0 ] || die "Sem terminal para confirmar. Rode em um terminal ou use YES=1."
  printf '%s [s/N] ' "$$1"; read -r ans
  case "$$ans" in s|S|sim|SIM|y|Y) return 0;; esac
  return 1
}
show_status() {
  run docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  ip=$$(hostname -I 2>/dev/null | awk '{print $$1}' || true)
  ip=$${ip:-IP-DO-SERVIDOR}
  printf '\nEndereços (troque o IP se acessar de fora da rede local):\n'
  for item in $(URLS); do printf '  %-12s http://%s:%s\n' "$${item%%:*}" "$$ip" "$${item##*:}"; done
}
do_clean() {
  failed=""
  for p in $$rprojects; do
    if [ ! -f "$$p/.env" ]; then warn "$$p: sem .env, ignorado"; continue; fi
    say "Limpando $$p"
    if ! (cd "$$p" && run docker compose down --remove-orphans --volumes --rmi all); then failed="$$failed $$p"; fi
  done
  [ -z "$$failed" ] || die "Falhou em:$$failed"
}
endef

# Funções para criar e apagar pastas com segurança (usadas por dirs e purge).
define FSLIB
mk() {
  o_uid=$$1; o_gid=$$2; shift 2
  for d in "$$@"; do
    [ -d "$$d" ] && continue
    parent=$$d
    while [ ! -d "$$parent" ]; do parent=$$(dirname "$$parent"); done
    if [ -w "$$parent" ] && [ "$$o_uid" = "$$(id -u)" ]; then
      run mkdir -p "$$d"
    else
      run $$S install -d -o "$$o_uid" -g "$$o_gid" -m 0755 "$$d"
    fi
  done
}
safe_path() {
  p=$$1
  case "$$p" in /*) ;; *) return 1;; esac
  case "$$p" in */..|*/../*|*/.|*/./*) return 1;; esac
  depth=$$(printf '%s' "$$p" | tr -cd '/' | wc -c)
  [ "$$depth" -ge 2 ] || return 1
  case "$$p" in
    /bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/lib|/lib/*|/lib32|/lib32/*|/lib64|/lib64/*) return 1;;
    /proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/sys|/sys/*|/usr|/usr/*) return 1;;
    /home/*/*) ;;
    /home/*) return 1;;
  esac
  case "$$ROOT/" in "$$p"/*) return 1;; esac
  return 0
}
wipe_dir() {
  d=$$1
  if run find "$$d" -xdev -mindepth 1 -delete 2>/dev/null; then return 0; fi
  run $$S find "$$d" -xdev -mindepth 1 -delete
}
endef

.PHONY: help up stop clean purge status check env dirs validate setup

help: ## Lista os alvos
	@printf 'Atalhos para o setup. O passo a passo manual continua valendo (docs/setup-passo-a-passo.md).\n'
	awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n%s\n", substr($$0,5)} /^[a-zA-Z_-]+:.*## /{printf "  make %-9s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	printf '\nOpção: YES=1 pula a pergunta do "make clean" (ex.: make clean YES=1).\n'

##@ Tudo de uma vez

up: setup ## Faz tudo: confere, prepara (.env e pastas), valida e sobe todos os serviços
	$(LIB)
	failed=""
	for p in $$projects; do
	  say "Subindo $$p"
	  if ! (cd "$$p" && run docker compose up -d); then
	    failed="$$failed $$p"
	    warn "$$p falhou (os outros projetos continuam)"
	  fi
	done
	echo
	show_status
	[ -z "$$failed" ] || die "Não subiram:$$failed. Veja o motivo com: cd <projeto> && docker compose logs"
	echo
	say "Tudo de pé. Próximo passo: configurar cada aplicação (docs/configuracao-inicial.md)."

stop: ## Para todos os containers (nada é removido; "make up" inicia de novo)
	$(LIB)
	failed=""
	for p in $$rprojects; do
	  if [ ! -f "$$p/.env" ]; then warn "$$p: sem .env, nada a parar"; continue; fi
	  say "Parando $$p"
	  if ! (cd "$$p" && run docker compose stop); then failed="$$failed $$p"; fi
	done
	[ -z "$$failed" ] || die "Falhou em:$$failed"
	ok "Tudo parado. Dados, containers e imagens continuam no disco."

clean: ## Para e REMOVE containers, redes, volumes e imagens (dados em disco e .env ficam)
	$(LIB)
	say "Vai remover containers, redes, volumes do Docker e as imagens baixadas."
	echo "    Seus dados em disco e os arquivos .env NÃO são apagados."
	confirm "Continuar?" || die "Cancelado."
	do_clean
	ok "Docker limpo. Para subir de novo: make up"

purge: ## CUIDADO: faz o clean e APAGA os dados (configs, mídia, fotos) e os .env
	$(LIB)
	$(FSLIB)
	for p in $$projects; do
	  [ -f "$$p/.env" ] || die "$$p/.env não existe: sem ele não sei quais pastas apagar."
	done
	declare -a targets=()
	for spec in media:CONFIG_DIR media:DATA_DIR immich:UPLOAD_LOCATION immich:DB_DATA_LOCATION dockhand:DOCKHAND_DIR; do
	  v=$$(envval "$${spec%%:*}" "$${spec##*:}")
	  [ -n "$$v" ] || die "$${spec##*:} está vazio em $${spec%%:*}/.env"
	  safe_path "$$v" || die "Caminho recusado por segurança: $$v"
	  dup=0
	  for t in "$${targets[@]:-}"; do [ "$$t" = "$$v" ] && dup=1; done
	  [ "$$dup" = 1 ] || targets+=("$$v")
	done
	printf '\n%sATENÇÃO: isto APAGA PERMANENTEMENTE o conteúdo de:%s\n' "$$R" "$$Z"
	for t in "$${targets[@]}"; do
	  sz=$$(du -sh "$$t" 2>/dev/null | cut -f1 || true)
	  printf '  - %s  (%s)\n' "$$t" "$${sz:-vazia ou inexistente}"
	done
	printf '  - os arquivos .env de: %s\n' "$$projects"
	printf '\nTambém remove containers, redes, volumes e imagens do Docker.\n'
	printf 'A pasta do repositório (%s) NÃO é tocada. As pastas acima ficam vazias.\n' "$$ROOT"
	printf 'Faça backup antes (docs/operacao-backup-acesso.md): fotos e banco do Immich não têm volta.\n\n'
	[ -t 0 ] || die "Sem terminal para confirmar. Rode 'make purge' direto em um terminal."
	printf 'Para continuar, digite APAGAR TUDO: '
	read -r ans
	[ "$$ans" = "APAGAR TUDO" ] || die "Cancelado. Nada foi apagado."
	do_clean
	for t in "$${targets[@]}"; do
	  [ -d "$$t" ] || continue
	  say "Apagando o conteúdo de $$t"
	  wipe_dir "$$t"
	done
	for p in $$projects; do run rm -f "$$p/.env"; done
	ok "Tudo apagado. Para recomeçar do zero: make up"

##@ Utilidades

status: ## Mostra os containers e os endereços de acesso
	$(LIB)
	show_status

backup-config: ## Backup das configurações dos apps em ~/backups/midia-server (sem sudo)
	$(LIB)
	run python3 "$$ROOT/scripts/backup-config.py"

##@ Passos individuais (cada um corresponde a um passo do setup manual)

check: ## Passo 2: confere Docker, Compose v2 e acesso ao daemon (não instala nada)
	$(LIB)
	say "Conferindo dependências"
	[ "$$(id -u)" -ne 0 ] || die "Não rode o make como root (sudo make): os .env ficariam com PUID=0. Rode como usuário comum; o make usa sudo só quando precisa."
	command -v docker >/dev/null 2>&1 || die "'docker' não encontrado. Instale conforme docs/requisitos-e-instalacao.md."
	ok "$$(docker --version 2>/dev/null | head -n1)"
	cv=$$(docker compose version 2>/dev/null | head -n1 || true)
	case "$$cv" in
	  "Docker Compose version v"[2-9]*|"Docker Compose version "[2-9]*) ok "$$cv";;
	  *) die "Precisa do Docker Compose v2 ou superior: 'docker compose version' deve mostrar 'Docker Compose version 2...' (ou v2...). Veja docs/requisitos-e-instalacao.md.";;
	esac
	docker info >/dev/null 2>&1 || die "Sem acesso ao daemon do Docker. Ele está rodando? Seu usuário tem permissão? (docs/requisitos-e-instalacao.md)"
	ok "Daemon do Docker acessível"
	if [ "$$(id -u)" != 1000 ]; then
	  warn "Seu UID é $$(id -u), não 1000. O Seerr sempre roda como 1000: 'make dirs' cria a pasta dele com esse dono."
	fi

env: ## Passos 3 e 6: cria os .env e preenche UID/GID, GID do docker e senha do Immich
	$(LIB)
	say "Preparando os arquivos .env"
	[ "$$(id -u)" -ne 0 ] || die "Não rode o make como root (sudo make): os .env ficariam com PUID=0. Rode como usuário comum."
	created=""
	for p in $$projects; do
	  [ -f "$$p/.env.example" ] || die "$$p/.env.example não encontrado"
	  if [ -f "$$p/.env" ]; then
	    ok "$$p/.env já existe (mantido)"
	  else
	    cp "$$p/.env.example" "$$p/.env"
	    created="$$created $$p"
	    ok "$$p/.env criado a partir do .env.example"
	  fi
	done
	is_new() { case " $$created " in *" $$1 "*) return 0;; esac; return 1; }
	for p in media dockhand; do
	  if is_new "$$p"; then
	    setval "$$p" PUID "$$(id -u)"
	    setval "$$p" PGID "$$(id -g)"
	    ok "$$p/.env: PUID=$$(id -u) PGID=$$(id -g)"
	  fi
	done
	if is_new dockhand || [ -z "$$(envval dockhand DOCKER_GID)" ]; then
	  gid=""
	  if [ -S /var/run/docker.sock ]; then gid=$$(stat -Lc %g /var/run/docker.sock 2>/dev/null || true); fi
	  [ -n "$$gid" ] || gid=$$(getent group docker 2>/dev/null | cut -d: -f3 || true)
	  if [ -n "$$gid" ]; then
	    setval dockhand DOCKER_GID "$$gid"
	    ok "dockhand/.env: DOCKER_GID=$$gid"
	  else
	    warn "Não achei o GID do socket/grupo docker. Ajuste DOCKER_GID em dockhand/.env (docs/setup-passo-a-passo.md, passo 3)."
	  fi
	fi
	if [ -z "$$(envval immich DB_PASSWORD)" ]; then
	  pw=$$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
	  setval immich DB_PASSWORD "$$pw"
	  ok "immich/.env: senha do Postgres gerada"
	fi
	[ -n "$$(envval immich DB_PASSWORD)" ] || die "immich/.env sem a linha DB_PASSWORD="
	for p in $$projects; do chmod 600 "$$p/.env"; done

dirs: env ## Passo 4: cria as pastas de dados e configuração (só as que faltam)
	$(LIB)
	$(FSLIB)
	say "Criando as pastas (só as que faltam)"
	uid=$$(envval media PUID); gid=$$(envval media PGID)
	config=$$(envval media CONFIG_DIR); data=$$(envval media DATA_DIR)
	photos=$$(envval immich UPLOAD_LOCATION); pgdata=$$(envval immich DB_DATA_LOCATION)
	dh=$$(envval dockhand DOCKHAND_DIR); stacks=$$(envval dockhand STACKS_DIR)
	for v in "$$uid" "$$gid" "$$config" "$$data" "$$photos" "$$pgdata" "$$dh" "$$stacks"; do
	  [ -n "$$v" ] || die "Variável vazia nos .env (PUID, PGID, CONFIG_DIR, DATA_DIR, UPLOAD_LOCATION, DB_DATA_LOCATION, DOCKHAND_DIR ou STACKS_DIR)"
	done
	for v in "$$config" "$$data" "$$photos" "$$pgdata" "$$dh" "$$stacks"; do
	  case "$$v" in /*) ;; *) die "Use caminhos absolutos nos .env: $$v";; esac
	done
	mk "$$uid" "$$gid" "$$data" "$$data/torrents" "$$data/torrents/movies" "$$data/torrents/tv" "$$data/media" "$$data/media/movies" "$$data/media/tv"
	mk "$$uid" "$$gid" "$$config"
	for app in qbittorrent prowlarr sonarr radarr bazarr jellyfin; do mk "$$uid" "$$gid" "$$config/$$app"; done
	mk 1000 1000 "$$config/seerr"
	mk "$$uid" "$$gid" "$$dh" "$$photos" "$$pgdata" "$$stacks"
	[ "$$(stat -c %u "$$config/seerr")" = 1000 ] || warn "$$config/seerr não pertence ao UID 1000: o Seerr pode falhar com 'permission denied'. Corrija: sudo chown 1000:1000 $$config/seerr"
	if [ "$$(stat -c %d "$$data/torrents")" != "$$(stat -c %d "$$data/media")" ]; then
	  warn "torrents/ e media/ estão em discos diferentes: hardlinks não funcionam e o espaço dobra (docs/aplicacoes.md)."
	fi
	ok "Pastas prontas"

validate: env ## Passo 7: valida os compose e as variáveis dos .env (docker compose config)
	$(LIB)
	say "Validando os compose"
	for p in $$projects; do
	  for name in $$(grep -oE '\$$\{[A-Za-z_][A-Za-z0-9_]*\}' "$$p/docker-compose.yml" | tr -d '$${}' | sort -u); do
	    [ -n "$$(envval "$$p" "$$name")" ] || die "$$p/.env: $$name está vazia ou ausente (o compose usa \$${$$name})"
	  done
	  out=$$(cd "$$p" && docker compose config -q 2>&1) || { printf '%s\n' "$$out" >&2; die "$$p: compose inválido"; }
	  ok "$$p"
	done

setup: check env dirs validate ## Passos 2 a 7 juntos, sem subir nada
