#!/usr/bin/env python3
"""Backup das configurações do servidor de mídia (sem sudo, sem parar nada).

Gera um .tar.gz datado com as configurações dos apps (/srv/config) e os arquivos
dos projetos (docker-compose e .env). Os bancos SQLite são copiados com a API de
backup do SQLite, que produz uma cópia consistente mesmo com o app rodando; um
"tar" simples pode copiar o banco no meio de uma gravação. Caches, logs, capas e
arquivos de transcodificação ficam de fora, pois são regenerados.

Opção:
  --if-older HORAS    só faz o backup se o último tiver mais de HORAS horas (sai em silêncio
                      se estiver recente). Serve para chamar de hora em hora pelo cron num
                      servidor que desliga ou suspende: o backup sai logo depois de ligar.

Variáveis opcionais:
  CONFIG_DIR          pasta das configurações            (padrão: /srv/config)
  BACKUP_DIR          onde guardar os arquivos           (padrão: ~/backups/midia-server)
  BACKUP_KEEP         quantos backups manter             (padrão: 14)
  BACKUP_SECOND_DEST  segunda pasta (HD externo, rede)   recebe uma cópia extra do arquivo
"""
import os
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/srv/config"))
DEST = Path(os.environ.get("BACKUP_DIR", Path.home() / "backups" / "midia-server"))
KEEP = int(os.environ.get("BACKUP_KEEP", "14"))
SECOND_DEST = os.environ.get("BACKUP_SECOND_DEST")

# Pastas (em qualquer nível) que não valem backup. O banco do Immich precisa de dump
# próprio (veja docs/operacao-backup-acesso.md): copiar os arquivos dele com o banco rodando não serve.
SKIP_DIRS = {"cache", ".cache", "logs", "log", "MediaCover", "transcodes", "immich-postgres"}
DB_SUFFIXES = (".db", ".sqlite", ".sqlite3")
SIDECAR_SUFFIXES = ("-wal", "-shm", "-journal")
PROJECTS = ("dockhand", "media", "immich")


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def is_sqlite(path):
    if path.suffix not in DB_SUFFIXES:
        return False
    try:
        with open(path, "rb") as f:
            return f.read(16) == b"SQLite format 3\x00"
    except OSError:
        return False


def copy_sqlite(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    source = sqlite3.connect(f"file:{src}?mode=ro", uri=True, timeout=30)
    try:
        target = sqlite3.connect(dst)
        try:
            source.backup(target)
        finally:
            target.close()
    finally:
        source.close()


def stage_config(stage):
    files = dbs = skipped = 0
    bad_dbs = []
    for dirpath, dirnames, filenames in os.walk(CONFIG_DIR):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel = Path(dirpath).relative_to(CONFIG_DIR)
        for name in filenames:
            if name.endswith(SIDECAR_SUFFIXES):
                continue
            src = Path(dirpath, name)
            dst = stage / "config" / rel / name
            try:
                if is_sqlite(src):
                    copy_sqlite(src, dst)
                    dbs += 1
                    check = sqlite3.connect(dst)
                    try:
                        if check.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                            bad_dbs.append(str(rel / name))
                    finally:
                        check.close()
                elif src.is_file() and not src.is_symlink():
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
                    files += 1
            except (OSError, sqlite3.Error) as e:
                skipped += 1
                log(f"aviso: ignorei {src}: {e}")
    return files, dbs, skipped, bad_dbs


def stage_project(stage):
    for project in PROJECTS:
        for pattern in ("docker-compose*.yml", ".env"):
            for f in (ROOT / project).glob(pattern):
                if f.is_file():
                    out = stage / "project" / project
                    out.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(f, out / f.name)
    try:  # referência para restaurar: quais imagens/containers existiam
        info = subprocess.run(["docker", "ps", "--format", "{{.Names}}  {{.Image}}"],
                              capture_output=True, text=True, timeout=30).stdout
        (stage / "containers.txt").write_text(info)
    except (OSError, subprocess.SubprocessError):
        pass


def rotate(folder):
    for old in sorted(folder.glob("midia-config-*.tar.gz"))[:-KEEP]:
        old.unlink()
        log(f"removido backup antigo: {old.name}")


def newest_age_hours(folder):
    archives = sorted(folder.glob("midia-config-*.tar.gz"))
    return (time.time() - archives[-1].stat().st_mtime) / 3600 if archives else None


def main():
    if not CONFIG_DIR.is_dir():
        sys.exit(f"erro: {CONFIG_DIR} não existe")
    if "--if-older" in sys.argv:
        try:
            hours = float(sys.argv[sys.argv.index("--if-older") + 1])
        except (IndexError, ValueError):
            sys.exit("uso: backup-config.py [--if-older HORAS]")
        age = newest_age_hours(DEST)
        if age is not None and age < hours:
            return 0  # backup recente: não faz nada e não escreve no log
    os.umask(0o077)  # o arquivo tem .env e chaves de API: só o dono lê
    DEST.mkdir(parents=True, exist_ok=True)
    name = f"midia-config-{time.strftime('%Y%m%d-%H%M%S')}.tar.gz"
    archive = DEST / name
    with tempfile.TemporaryDirectory(prefix=".staging-", dir=DEST) as tmp:
        stage = Path(tmp) / "midia-server"
        files, dbs, skipped, bad_dbs = stage_config(stage)
        stage_project(stage)
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(stage, arcname="midia-server")
    size_mb = archive.stat().st_size / 1e6
    log(f"backup ok: {archive} ({size_mb:.1f} MB; {files} arquivos, {dbs} bancos SQLite, {skipped} ignorados)")
    if bad_dbs:
        log(f"ATENÇÃO: integrity_check falhou em: {', '.join(bad_dbs)}")
    rotate(DEST)
    if SECOND_DEST:
        second = Path(SECOND_DEST)
        if second.is_dir():
            shutil.copy2(archive, second / name)
            rotate(second)
            log(f"cópia extra gravada em {second}")
        else:
            log(f"aviso: BACKUP_SECOND_DEST ({second}) não existe ou não está montado")
    return 1 if bad_dbs else 0


if __name__ == "__main__":
    sys.exit(main())
