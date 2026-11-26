#!/usr/bin/env python3
"""CastroCloud · Informe diario do estado dos servidores, cos datos de Zabbix.

Pide á API de Zabbix os datos das últimas 24 horas e xera unha páxina HTML:
  - cada servidor: se o axente responde, CPU, memoria e disco (media e máximo);
  - os problemas abertos agora e os que houbo nas últimas 24 horas.

Só usa a biblioteca estándar de Python 3 (sen instalar nada).

Ansible instálao en ct-zabbix e execútao cada día ás 07:00 (cron), cos datos
de acceso en /etc/castrocloud/informe-zabbix.ini. Tamén se pode lanzar a man
desde o equipo de Eloy e abrir o informe no navegador:

  python3 informe-zabbix.py --url http://10.10.20.11 \\
      --contrasinal-ficheiro ../ansible/segredos/zabbix_admin --saida informe.html
"""

import argparse
import configparser
import html
import json
import statistics
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

# Elementos dos modelos «Linux by Zabbix agent active» que se resumen
INDICADORES = {
    "system.cpu.util": "CPU",
    "vm.memory.util": "Memoria",
    "vfs.fs.dependent.size[/,pused]": "Disco /",
}
GRAVIDADE = ["Sen clasificar", "Información", "Aviso", "Media", "Alta", "Desastre"]
COR_GRAVIDADE = ["#97aab3", "#7499ff", "#ffc859", "#ffa059", "#e97659", "#e45959"]


class Zabbix:
    """Cliente mínimo da API JSON-RPC de Zabbix."""

    def __init__(self, url, usuario, contrasinal):
        self.url = url.rstrip("/") + "/api_jsonrpc.php"
        self.token = None
        self.token = self.chamar("user.login", {"username": usuario, "password": contrasinal})

    def chamar(self, metodo, parametros):
        corpo = json.dumps({"jsonrpc": "2.0", "method": metodo, "params": parametros, "id": 1}).encode()
        cabeceiras = {"Content-Type": "application/json-rpc"}
        if self.token:
            cabeceiras["Authorization"] = f"Bearer {self.token}"
        peticion = urllib.request.Request(self.url, data=corpo, headers=cabeceiras)
        with urllib.request.urlopen(peticion, timeout=30) as resposta:
            datos = json.load(resposta)
        if "error" in datos:
            raise RuntimeError(f"{metodo}: {datos['error'].get('data') or datos['error']['message']}")
        return datos["result"]


def recoller(zbx, horas=24):
    """Devolve os servidores coas súas medidas e os problemas."""
    dende = int(time.time()) - horas * 3600
    servidores = zbx.chamar("host.get", {
        "output": ["hostid", "host", "active_available"],
        "filter": {"status": 0},
        "sortfield": "host",
    })
    elementos = zbx.chamar("item.get", {
        "output": ["itemid", "hostid", "key_", "value_type", "lastvalue"],
        "hostids": [s["hostid"] for s in servidores],
        "filter": {"key_": list(INDICADORES)},
    })

    medidas = {}   # (hostid, clave) -> {media, maximo, ultimo}
    for el in elementos:
        historia = zbx.chamar("history.get", {
            "output": ["value"], "itemids": el["itemid"], "history": int(el["value_type"]),
            "time_from": dende, "sortfield": "clock",
        })
        valores = [float(h["value"]) for h in historia]
        if valores:
            medidas[(el["hostid"], el["key_"])] = {
                "media": statistics.fmean(valores), "maximo": max(valores), "ultimo": valores[-1],
            }

    abertos = zbx.chamar("problem.get", {
        "output": ["eventid", "objectid", "name", "severity", "clock"],
        "sortfield": ["eventid"], "sortorder": "DESC",
    })
    eventos = zbx.chamar("event.get", {
        "output": ["eventid", "name", "severity", "clock", "r_eventid"],
        "selectHosts": ["host"], "source": 0, "object": 0, "value": 1,
        "time_from": dende, "sortfield": ["clock"], "sortorder": "DESC",
    })
    # Os problemas abertos non traen o servidor: búscase polo seu disparador
    disparadores = {}
    if abertos:
        for d in zbx.chamar("trigger.get", {
            "output": ["triggerid"], "selectHosts": ["host"],
            "triggerids": list({p["objectid"] for p in abertos}),
        }):
            disparadores[d["triggerid"]] = ", ".join(h["host"] for h in d["hosts"])
    for p in abertos:
        p["servidor"] = disparadores.get(p["objectid"], "?")
    for e in eventos:
        e["servidor"] = ", ".join(h["host"] for h in e.get("hosts", []))

    return servidores, medidas, abertos, eventos


def porcentaxe(medida):
    if not medida:
        return '<td class="sen">—</td>'
    clase = "alto" if medida["maximo"] >= 90 else "medio" if medida["maximo"] >= 75 else ""
    return (f'<td class="{clase}">{medida["media"]:.0f} % '
            f'<small>(máx. {medida["maximo"]:.0f} %)</small></td>')


def data(segundos):
    return datetime.fromtimestamp(int(segundos)).strftime("%d/%m %H:%M")


def html_informe(servidores, medidas, abertos, eventos, horas):
    agora = datetime.now().strftime("%d/%m/%Y %H:%M")
    filas = []
    for s in servidores:
        axente = ('<td class="ok">Responde</td>' if s["active_available"] == "1"
                  else '<td class="alto">Non responde</td>')
        celas = "".join(porcentaxe(medidas.get((s["hostid"], k))) for k in INDICADORES)
        filas.append(f"<tr><td>{html.escape(s['host'])}</td>{axente}{celas}</tr>")

    def lista(problemas, con_estado):
        if not problemas:
            return '<p class="ok">Ningún.</p>'
        linhas = []
        for p in problemas:
            g = int(p["severity"])
            estado = ""
            if con_estado:
                estado = "<td>Resolto</td>" if p.get("r_eventid", "0") != "0" else '<td class="alto">Aberto</td>'
            linhas.append(
                f'<tr><td><span class="grav" style="background:{COR_GRAVIDADE[g]}">{GRAVIDADE[g]}</span></td>'
                f"<td>{html.escape(p['servidor'])}</td><td>{html.escape(p['name'])}</td>"
                f"<td>{data(p['clock'])}</td>{estado}</tr>")
        cab = "<th>Gravidade</th><th>Servidor</th><th>Problema</th><th>Desde</th>"
        if con_estado:
            cab += "<th>Estado</th>"
        return f"<table><tr>{cab}</tr>{''.join(linhas)}</table>"

    cab_indicadores = "".join(f"<th>{n} <small>media {horas} h</small></th>" for n in INDICADORES.values())
    resumo = ("Todo en orde" if not abertos and all(s["active_available"] == "1" for s in servidores)
              else f"{len(abertos)} problemas abertos")
    return f"""<!doctype html>
<html lang="gl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Informe CastroCloud {agora}</title>
<style>
 body{{font-family:Arial,Helvetica,sans-serif;margin:2rem auto;max-width:960px;padding:0 1rem;color:#222}}
 h1{{color:#1f4e79;margin-bottom:.2rem}} h2{{color:#1f4e79;border-bottom:2px solid #1f4e79;padding-bottom:.2rem}}
 table{{border-collapse:collapse;width:100%;margin-bottom:1rem}}
 th,td{{border:1px solid #ccc;padding:.4rem .6rem;text-align:left;font-size:.95rem}}
 th{{background:#1f4e79;color:#fff}} small{{color:#666}} th small{{color:#dde}}
 .ok{{color:#1e7b34}} .medio{{background:#fff4d6}} .alto{{background:#fde2e1;color:#a11}}
 .sen{{color:#999}} .grav{{color:#000;padding:.1rem .4rem;border-radius:3px;font-size:.85rem}}
 .resumo{{font-size:1.2rem;font-weight:bold}}
</style></head><body>
<h1>CastroCloud · Informe diario dos servidores</h1>
<p>Xerado o {agora} cos datos de Zabbix das últimas {horas} horas.</p>
<p class="resumo">{resumo}</p>
<h2>Servidores</h2>
<table><tr><th>Servidor</th><th>Axente</th>{cab_indicadores}</tr>{''.join(filas)}</table>
<p><small>Fondo amarelo: máximo por riba do 75 %; vermello: por riba do 90 %.</small></p>
<h2>Problemas abertos agora</h2>
{lista(abertos, False)}
<h2>Problemas das últimas {horas} horas</h2>
{lista(eventos, True)}
</body></html>
"""


def main():
    p = argparse.ArgumentParser(description="Informe diario de CastroCloud cos datos de Zabbix")
    p.add_argument("--config", default="/etc/castrocloud/informe-zabbix.ini",
                   help="ficheiro con url, usuario, contrasinal e directorio (sección [zabbix])")
    p.add_argument("--url", help="URL da web de Zabbix, p. ex. http://10.10.20.11")
    p.add_argument("--usuario", help="usuario de Zabbix (por defecto Admin)")
    p.add_argument("--contrasinal-ficheiro", help="ficheiro co contrasinal (mellor que escribilo na orde)")
    p.add_argument("--saida", help="ficheiro HTML de saída (por defecto, un por día no directorio)")
    p.add_argument("--horas", type=int, default=24, help="período do informe en horas (24)")
    args = p.parse_args()

    conf = configparser.ConfigParser()
    conf.read(args.config)
    z = conf["zabbix"] if conf.has_section("zabbix") else {}
    url = args.url or z.get("url")
    usuario = args.usuario or z.get("usuario", "Admin")
    if args.contrasinal_ficheiro:
        contrasinal = Path(args.contrasinal_ficheiro).read_text().strip()
    else:
        contrasinal = z.get("contrasinal")
    if not url or not contrasinal:
        sys.exit(f"ERRO: faltan a URL ou o contrasinal (--url e --contrasinal-ficheiro, ou {args.config})")

    saida = Path(args.saida) if args.saida else (
        Path(z.get("directorio", "/opt/castrocloud/informes")) / f"informe-{datetime.now():%Y-%m-%d}.html")
    saida.parent.mkdir(parents=True, exist_ok=True)

    try:
        datos = recoller(Zabbix(url, usuario, contrasinal), args.horas)
    except Exception as e:   # erro de rede ou da API: mensaxe clara e código de saída 1
        sys.exit(f"ERRO ao falar con Zabbix ({url}): {e}")

    saida.write_text(html_informe(*datos, args.horas), encoding="utf-8")
    servidores, _, abertos, eventos = datos
    print(f"Informe gardado en {saida}: {len(servidores)} servidores, "
          f"{len(abertos)} problemas abertos, {len(eventos)} nas últimas {args.horas} h")


if __name__ == "__main__":
    main()
