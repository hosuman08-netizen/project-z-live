#!/usr/bin/env bash
# PROJECT Z — status JSON + (optional) commit/push if json changed
# 모델 호출 없음. runs 원본·키 절대 커밋 안 함.
set -euo pipefail
export PATH="/Library/Frameworks/Python.framework/Versions/3.13/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${HOME}/homebrew/bin:${HOME}/.local/bin:${PATH}"

SITE="$(cd "$(dirname "$0")" && pwd)"
RUNS="$HOME/legion/legion-graph/runs"
GRAPH="$HOME/legion/legion-graph"
OUT="$SITE/legion-status.json"
LOG="$SITE/cron.log"

ts_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# --- provider ---
prov="unknown"
brain_ok=false
if status_out=$(cd "$GRAPH" && uv run legion-graph status 2>/dev/null); then
  prov=$(printf '%s\n' "$status_out" | awk -F'= *' '/provider_resolved/{print $2; exit}')
  [[ -z "$prov" ]] && prov=$(printf '%s\n' "$status_out" | awk -F'= *' '/provider_auto/{print $2; exit}')
  key_line=$(printf '%s\n' "$status_out" | grep -E 'anthropic_key=|openai_key=' || true)
  if printf '%s' "$key_line" | grep -q 'yes'; then brain_ok=true; fi
  if [[ "$prov" == "ollama" ]]; then brain_ok=true; fi
fi
[[ -z "$prov" ]] && prov="unknown"

# --- runs → sanitized status adapter ---
ADAPTER="${AGENT_OS_STATUS_ADAPTER:-$HOME/legion/seats/altman/agent-os/status_adapter.py}"
export RUNS OUT
export BRAIN_PROV="$prov"
export BRAIN_OK="$brain_ok"
python3 "$ADAPTER"

# Public board only: seat names → role labels. Internal files/terminals unchanged.
python3 <<'PY'
import json, os, re
from pathlib import Path
PUBLIC = {
    "jarvis": "chief-of-staff",
    "trinity": "product",
    "morpheus": "ops",
    "oracle": "audit",
    "altman": "engineering",
    "graph": "core-graph",
    "silas": "research",
    "ghostwire": "osint",
    "tank": "architecture",
    "jensen": "compute",
    "niobe": "growth",
    "plutus": "finance",
    "guardian-atlas": "guardian",
    "seraph": "marketing",
    "persephone": "conversion",
    "qa-runtime": "qa",
    "ship-deploy": "ship",
    "cpo-product": "product",
}
DROP_NOTE = {"ceo", "cpo", "coo", "cdo", "cto", "cmo", "cfo", "cwo", "orchestration"}

def pub(raw: str) -> str:
    k = str(raw or "").strip().lower()[:40]
    if k in PUBLIC:
        return PUBLIC[k]
    if k in PUBLIC.values():
        return k
    slug = re.sub(r"[^a-z0-9-]", "", k)
    return slug or "crew"

out = Path(os.environ["OUT"])
d = json.loads(out.read_text(encoding="utf-8"))
merged = {}
for a in d.get("agents") or []:
    if not isinstance(a, dict):
        continue
    pid = pub(a.get("id"))
    a["id"] = pid
    prev = merged.get(pid)
    if prev is None or str(a.get("last_run") or "") >= str(prev.get("last_run") or ""):
        merged[pid] = a
d["agents"] = sorted(merged.values(), key=lambda x: str(x.get("last_run") or ""), reverse=True)
IP = ("jarvis", "trinity", "morpheus", "oracle", "altman")

def scrub(s: str) -> str:
    t = str(s or "")
    for k in IP:
        t = re.sub(r"(?i)(?<![a-z0-9])" + re.escape(k) + r"(?![a-z0-9])", PUBLIC[k], t)
    return t

def scrub_obj(o):
    if isinstance(o, dict):
        return {k: scrub_obj(v) for k, v in o.items()}
    if isinstance(o, list):
        return [scrub_obj(v) for v in o]
    if isinstance(o, str):
        return scrub(o)
    return o

for r in d.get("runs") or []:
    if not isinstance(r, dict):
        continue
    r["agent"] = pub(r.get("agent"))
    note = str(r.get("note") or "").strip().lower()
    if note in DROP_NOTE or note in PUBLIC:
        r["note"] = ""
d = scrub_obj(d)
out.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(str(out) + " public-labels")
PY

# Legacy inline generator retained as disabled rollback reference; the adapter above is authoritative.
if false; then
export RUNS OUT
export BRAIN_PROV="$prov"
export BRAIN_OK="$brain_ok"
python3 <<'PY'
import json, os, re, datetime
from pathlib import Path

runs_dir = Path(os.environ["RUNS"])
out = Path(os.environ["OUT"])
prov = os.environ.get("BRAIN_PROV") or "unknown"
brain_ok = os.environ.get("BRAIN_OK") == "true"

SKIP = {"LIVE_BOARD.json"}
SECRET = re.compile(
    r"(sk-[A-Za-z0-9_-]{8,}|lsv2_[A-Za-z0-9_]+|gho_[A-Za-z0-9]+|ghp_[A-Za-z0-9]+|"
    r"AKIA[0-9A-Z]{8,}|api[_-]?key\s*[:=]\s*\S+|BOT_TOKEN|ANTHROPIC_API_KEY|"
    r"OPENAI_API_KEY|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})",
    re.I,
)

def iso_mtime(p: Path) -> str:
    return datetime.datetime.fromtimestamp(p.stat().st_mtime, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def clean(s: str, n: int = 80) -> str:
    s = SECRET.sub("[redacted]", s or "")
    s = re.sub(r"\s+", " ", s).strip()
    return s[:n]

# Public board only. Internal files/terminals keep seat names.
PUBLIC_ID = {
    "jarvis": "chief-of-staff",
    "trinity": "product",
    "morpheus": "ops",
    "oracle": "audit",
    "altman": "engineering",
    "graph": "core-graph",
    "silas": "research",
    "ghostwire": "osint",
    "tank": "architecture",
    "jensen": "compute",
    "niobe": "growth",
    "plutus": "finance",
    "guardian-atlas": "guardian",
    "seraph": "marketing",
    "persephone": "conversion",
    "qa-runtime": "qa",
    "ship-deploy": "ship",
    "cpo-product": "product",
}

def public_id(raw: str) -> str:
    k = (raw or "").strip().lower()[:40]
    if k in PUBLIC_ID:
        return PUBLIC_ID[k]
    if k in PUBLIC_ID.values():
        return k
    slug = re.sub(r"[^a-z0-9-]", "", k)
    return slug or "crew"

def note_from(agent: str, ok: bool) -> str:
    # page already renders 성공/실패 from ok. agent id is the public role label.
    return ""

def ok_of(d: dict):
    if isinstance(d.get("ok"), bool):
        return d["ok"]
    if isinstance(d.get("pass"), bool):
        return d["pass"]
    if str(d.get("verdict") or "").upper() == "FAIL":
        return False
    if str(d.get("status") or "").upper() in ("FAIL", "FAILED", "ERROR"):
        return False
    if str(d.get("status") or "").upper() in ("OK", "PASS", "DONE"):
        return True
    return True  # live summon without ok field: treat as completed call

def agent_of(p: Path, d: dict) -> str:
    a = d.get("agent") or d.get("id")
    if isinstance(a, str) and a.strip() and a not in ("graph",):
        return a.strip()[:40]
    name = p.stem
    m = re.match(r"live-([a-z0-9_-]+)-", name, re.I)
    if m:
        return m.group(1)
    if name.startswith("hardcheck"):
        return "oracle"
    if name.startswith("graph"):
        return "graph"
    return name[:40]

files = [p for p in runs_dir.glob("*.json") if p.name not in SKIP]
files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
files = files[:20]

runs = []
agents = {}
for p in files:
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        if not isinstance(d, dict):
            continue
    except Exception:
        continue
    ts = d.get("updated") or d.get("started") or d.get("finished") or iso_mtime(p)
    if not isinstance(ts, str) or "T" not in ts:
        ts = iso_mtime(p)
    agent = public_id(agent_of(p, d))
    ok = bool(ok_of(d))
    note = note_from(agent, ok)
    runs.append({"ts": ts, "agent": agent, "ok": ok, "note": note})
    prev = agents.get(agent)
    if not prev or ts >= prev["last_run"]:
        agents[agent] = {"id": agent, "last_run": ts, "ok": bool(ok)}
    # graph runs also stamp core seats if present (never overwrite a newer run)
    if p.stem.startswith("graph"):
        for seat in ("jarvis", "trinity", "morpheus", "oracle"):
            if seat in d and isinstance(d[seat], str) and d[seat].strip():
                pub = public_id(seat)
                prev = agents.get(pub)
                if not prev or ts >= prev["last_run"]:
                    agents[pub] = {"id": pub, "last_run": ts, "ok": bool(ok)}

agent_list = list(agents.values())
agent_list.sort(key=lambda a: a.get("last_run") or "", reverse=True)

payload = {
    "updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "brain": {"provider": prov, "ok": brain_ok},
    "agents": agent_list,
    "runs": runs,
}
if out.exists():
    try:
        old = json.loads(out.read_text(encoding="utf-8"))
        if (
            old.get("brain") == payload["brain"]
            and old.get("agents") == payload["agents"]
            and old.get("runs") == payload["runs"]
        ):
            print(str(out) + " unchanged")
            raise SystemExit(0)
    except SystemExit:
        raise
    except Exception:
        pass
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(str(out))
PY
fi

# --- git: json changed only ---
if [[ ! -d "$SITE/.git" ]]; then
  log "json written, no git repo yet"
  exit 0
fi
cd "$SITE"
git add -A -- legion-status.json >/dev/null 2>&1 || true
if git diff --cached --quiet -- legion-status.json 2>/dev/null; then
  log "no json change"
  git reset -q HEAD -- legion-status.json 2>/dev/null || true
  exit 0
fi
git commit -q -m "status $(ts_iso)" -- legion-status.json
if git push -q origin HEAD 2>>"$LOG"; then
  log "pushed status"
else
  log "push FAIL"
  exit 1
fi
