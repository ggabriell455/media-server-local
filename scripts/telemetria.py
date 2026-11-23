#!/usr/bin/env python3
"""Coleta temperatura, ventoinhas, frequência, GPUs e containers em um CSV.

Pensado para rodar a cada poucos minutos pelo cron e responder, dias depois, perguntas como
"esquentou?", "a RTX ficou acordada o tempo todo?" e "quanto a CPU consumiu?".

- Só lê arquivos de /sys e roda `docker ps`/`nvidia-smi`. Não precisa de root e não altera nada.
- NÃO acorda a RTX: só consulta o nvidia-smi quando o kernel já mostra a GPU como "active".
  (Consultar uma GPU suspensa a acordaria e falsearia justamente o consumo que queremos medir.)
- A potência da CPU (RAPL) só é lida se o arquivo for legível; por padrão ele é só de root.
  Para habilitar até o próximo boot: sudo chmod -R a+r /sys/class/powercap/intel-rapl:0

Uso: telemetria.py [pasta-de-saida]   (padrão: ~/telemetria-servidor)
"""
import csv
import glob
import os
import subprocess
import sys
import time
from pathlib import Path

OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "telemetria-servidor"
CSV_PATH = OUT_DIR / "telemetria.csv"
STATE_PATH = OUT_DIR / ".rapl-estado"
RAPL = Path("/sys/class/powercap/intel-rapl:0/energy_uj")
HEADER = [
    "data_hora", "cpu_pacote_c", "cpu_mhz_medio", "carga_1min", "cpu_pacote_w",
    "ventoinha1_rpm", "ventoinha2_rpm", "acer_temp1_c", "acer_temp2_c", "acer_temp3_c",
    "nvme0_composto_c", "nvme0_max_sensor_c", "nvme1_composto_c", "nvme1_max_sensor_c",
    "igpu_mhz", "rtx_estado", "rtx_util_pct", "rtx_mem_mib", "rtx_temp_c", "rtx_w",
    "bateria_estado", "bateria_pct", "containers_ok", "containers_total",
]


def read(path, default=None):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def milli(path):
    value = read(path)
    return round(int(value) / 1000, 1) if value and value.lstrip("-").isdigit() else ""


def hwmons():
    found = {}
    for d in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        found.setdefault(read(f"{d}/name", ""), []).append(d)
    return found


def nvme_temps(d):
    comp = milli(f"{d}/temp1_input")
    sensors = [milli(f) for f in sorted(glob.glob(f"{d}/temp[2-9]_input"))]
    sensors = [s for s in sensors if s != ""]
    return comp, (max(sensors) if sensors else "")


def cpu_watts():
    """Watts médios desde a amostra anterior, ou "" se o RAPL não for legível."""
    energy = read(RAPL)
    if not energy or not energy.isdigit():
        return ""
    now, uj = time.time(), int(energy)
    watts = ""
    prev = read(STATE_PATH)
    if prev:
        try:
            t0, e0 = prev.split()
            dt, de = now - float(t0), uj - int(e0)
            if dt > 0 and de >= 0:  # de < 0: o contador deu a volta; ignora esta amostra
                watts = round(de / 1e6 / dt, 1)
        except ValueError:
            pass
    STATE_PATH.write_text(f"{now} {uj}")
    return watts


def rtx():
    """(estado, util%, mem MiB, temp C, W). Só consulta o nvidia-smi se a GPU já estiver acordada."""
    for dev in glob.glob("/sys/bus/pci/devices/*"):
        if read(f"{dev}/vendor") == "0x10de" and (read(f"{dev}/class", "") or "").startswith("0x03"):
            state = read(f"{dev}/power/runtime_status", "?")
            if state != "active":
                return state, "", "", "", ""
            try:
                out = subprocess.run(
                    ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,temperature.gpu,power.draw",
                     "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=10, check=True).stdout.strip().split(", ")
                return (state, *out[:4])
            except (OSError, subprocess.SubprocessError, ValueError):
                return state, "", "", "", ""
    return "ausente", "", "", "", ""


def igpu_mhz():
    for card in glob.glob("/sys/class/drm/card[0-9]"):
        if read(f"{card}/device/vendor") == "0x8086":
            return read(f"{card}/gt_act_freq_mhz", "")
    return ""


def containers():
    try:
        out = subprocess.run(["docker", "ps", "--format", "{{.Status}}"],
                             capture_output=True, text=True, timeout=15, check=True).stdout.splitlines()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    return sum("(healthy)" in s for s in out), len(out)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    hw = hwmons()
    core = (hw.get("coretemp") or [None])[0]
    acer = (hw.get("acer") or [None])[0]
    freqs = [int(v) for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")
             if (v := read(f)) and v.isdigit()]
    nvme = (hw.get("nvme") or []) + [None, None]
    n0, n1 = (nvme_temps(nvme[0]) if nvme[0] else ("", "")), (nvme_temps(nvme[1]) if nvme[1] else ("", ""))
    bat = next(iter(glob.glob("/sys/class/power_supply/BAT*")), None)
    ok, total = containers()
    row = [
        time.strftime("%Y-%m-%d %H:%M:%S"),
        milli(f"{core}/temp1_input") if core else "",
        round(sum(freqs) / len(freqs) / 1000) if freqs else "",
        (read("/proc/loadavg", "") or "").split(" ")[0],
        cpu_watts(),
        read(f"{acer}/fan1_input", "") if acer else "", read(f"{acer}/fan2_input", "") if acer else "",
        *(milli(f"{acer}/temp{i}_input") if acer else "" for i in (1, 2, 3)),
        *n0, *n1,
        igpu_mhz(), *rtx(),
        read(f"{bat}/status", "") if bat else "", read(f"{bat}/capacity", "") if bat else "",
        ok, total,
    ]
    new = not CSV_PATH.exists()
    with CSV_PATH.open("a", newline="") as fh:
        writer = csv.writer(fh)
        if new:
            writer.writerow(HEADER)
        writer.writerow(row)


if __name__ == "__main__":
    main()
