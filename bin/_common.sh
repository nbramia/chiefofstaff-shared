# shellcheck shell=bash
# Shared helpers for chiefofstaff scripts. Source it: . "$(dirname "$0")/_common.sh"
# Reads the operator's settings from chiefofstaff.conf (see chiefofstaff.conf.example).

CHIEFOFSTAFF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${CHIEFOFSTAFF_LEDGER:-$CHIEFOFSTAFF_DIR/ledger.md}"   # CHIEFOFSTAFF_LEDGER: tests only
CHIEFOFSTAFF_CONFIG="${CHIEFOFSTAFF_CONFIG:-$CHIEFOFSTAFF_DIR/chiefofstaff.conf}"

if [ ! -f "$CHIEFOFSTAFF_CONFIG" ]; then
  echo "chiefofstaff: NOT CONFIGURED: $CHIEFOFSTAFF_CONFIG doesn't exist. Run the onboarding interview (AGENTS.md → Onboarding)." >&2
  exit 4
fi
OPERATOR_NAME=""; CHIEFOFSTAFF_REL=""; PROJECTS_REL=""; GITHUB_OWNER=""; NOTIFY_CMD=""; MACHINES=()
# shellcheck source=/dev/null
. "$CHIEFOFSTAFF_CONFIG"
OPERATOR_NAME="${OPERATOR_NAME:-the operator}"
CHIEFOFSTAFF_REL="${CHIEFOFSTAFF_REL:-Code/chiefofstaff}"
export OPERATOR_NAME

# git pull, unless CHIEFOFSTAFF_NO_PULL=1 (tests).
chiefofstaff_pull() { [ -n "${CHIEFOFSTAFF_NO_PULL:-}" ] || git -C "$CHIEFOFSTAFF_DIR" pull -q --ff-only; }

# Machines, from MACHINES ("name|hostname|orca-environment|ssh-alias" each). This machine is
# the one whose hostname matches `hostname -s` (CHIEFOFSTAFF_MACHINE=<name> overrides). The
# others are OTHER_HOSTS, with their Orca environment names (OTHER_ENVS) and ssh aliases
# (OTHER_SSHS) at the same index. OTHER_HOST/OTHER_ENV/OTHER_SSH are the first of them.
CHIEFOFSTAFF_HOST=""; OTHER_HOSTS=(); OTHER_ENVS=(); OTHER_SSHS=()
_cos_hn="$(hostname -s 2>/dev/null || hostname)"
for _cos_m in "${MACHINES[@]}"; do
  IFS='|' read -r _cos_n _cos_h _cos_e _cos_s <<<"$_cos_m"
  if [ -z "$CHIEFOFSTAFF_HOST" ] && { [ "${CHIEFOFSTAFF_MACHINE:-}" = "$_cos_n" ] \
       || { [ -z "${CHIEFOFSTAFF_MACHINE:-}" ] && [ "$_cos_h" = "$_cos_hn" ]; }; }; then
    CHIEFOFSTAFF_HOST="$_cos_n"
  else
    OTHER_HOSTS+=("$_cos_n"); OTHER_ENVS+=("$_cos_e"); OTHER_SSHS+=("$_cos_s")
  fi
done
unset _cos_m _cos_n _cos_h _cos_e _cos_s
if [ -z "$CHIEFOFSTAFF_HOST" ]; then
  echo "chiefofstaff: this machine (hostname ${CHIEFOFSTAFF_MACHINE:-$_cos_hn}) isn't in MACHINES in $CHIEFOFSTAFF_CONFIG. Add it (AGENTS.md → Onboarding)." >&2
  exit 4
fi
unset _cos_hn
OTHER_HOST="${OTHER_HOSTS[0]:-}"; OTHER_ENV="${OTHER_ENVS[0]:-}"; OTHER_SSH="${OTHER_SSHS[0]:-}"

# machine_field <name> env|ssh|hostname: one field of a configured machine (empty if unknown).
machine_field() {
  local m n h e s
  for m in "${MACHINES[@]}"; do
    IFS='|' read -r n h e s <<<"$m"
    [ "$n" = "$1" ] || continue
    case "$2" in env) echo "$e" ;; ssh) echo "$s" ;; hostname) echo "$h" ;; esac
    return 0
  done
}

# The Orca app's CLI. Known install paths come first: timers run without the login PATH,
# and on Ubuntu /usr/bin/orca is the GNOME screen reader, which hangs instead of failing.
if [ -z "${ORCA:-}" ]; then
  for c in "$HOME/.config/orca/linux-orca-cli-shim/orca" /usr/local/bin/orca; do
    [ -x "$c" ] && { ORCA="$c"; break; }
  done
fi
if [ -z "${ORCA:-}" ]; then
  ORCA="$(command -v orca 2>/dev/null || true)"
  [ "$ORCA" != /usr/bin/orca ] || ORCA=""
fi
[ -n "$ORCA" ] || { echo "chiefofstaff: Orca's CLI not found" >&2; exit 1; }

# Ledger → "## Chiefofstaff run" section: "- Host: <machine>" and "- Run: `run_…`".
ledger_field() {  # ledger_field Host|Run
  sed -n '/^## Chiefofstaff run/,/^## /p' "$LEDGER" | sed -nE "s/^- $1: \`?([^\` ]+)\`?.*/\1/p" | head -1
}

ledger_set_run() {  # ledger_set_run <host> <run>
  python3 - "$LEDGER" "$1" "$2" <<'PY'
import re, sys
p, host, run = sys.argv[1:4]
s = open(p).read()
block = (f"## Chiefofstaff run\n\n- Host: {host}\n- Run: `{run}`\n\n"
         "Chiefofstaff runs on one machine at a time; its run lives in that machine's Orca.\n"
         "`bin/start-chiefofstaff` maintains this section and `bin/sitrep-ping` reads it.\n")
if "## Chiefofstaff run" in s:
    s = re.sub(r"## Chiefofstaff run\n.*?(?=\n## )", block, s, count=1, flags=re.S)
else:
    s = s.replace("## Machines", block + "\n## Machines", 1)
open(p, "w").write(s)
PY
}

# Number of agent sessions open in the chiefofstaff workspace (~/$CHIEFOFSTAFF_REL, not
# admin/…) on this machine, or on another with: chiefofstaff_sessions --environment <env>
chiefofstaff_sessions() {
  "$ORCA" worktree ps --json "$@" 2>/dev/null | python3 -c '
import json, sys
rel = "/" + sys.argv[1].strip("/")
try:
    d = json.load(sys.stdin)
except Exception:
    print(-1); sys.exit()
r = d.get("result", d)
ws = r.get("worktrees", []) if isinstance(r, dict) else r
n = 0
for w in ws:
    if (w.get("path") or "").rstrip("/").endswith(rel):
        n += len(w.get("agents") or [])
print(n)' "$CHIEFOFSTAFF_REL"
}

# Ledger → "## Open cards": one "- <project>: <question in a few words> (asked YYYY-MM-DD)"
# line per card put to the operator and not yet answered. Prints those lines; nothing if none.
ledger_open_cards() {
  sed -n '/^## Open cards/,/^## /p' "$LEDGER" | grep '^- ' || true
}

# Project entries under "## Projects" longer than LEDGER_ENTRY_WORDS words (default 120),
# one "<project>: <n> words" line each. Entries hold current state only; history is git's.
ledger_long_entries() {
  python3 - "$LEDGER" "${LEDGER_ENTRY_WORDS:-120}" <<'PY'
import re, sys
s, limit = open(sys.argv[1]).read(), int(sys.argv[2])
m = re.search(r"^## Projects\n(.*?)(?=^## |\Z)", s, flags=re.M | re.S)
body = m.group(1) if m else ""
for e in re.split(r"(?m)^(?=- \*\*)", body):
    name = re.match(r"- \*\*(.+?)\*\*", e)
    if name and len(e.split()) > limit:
        print(f"{name.group(1)}: {len(e.split())} words")
PY
}

# Run Orca as nobody: a caller's Orca session id only identifies it on its own host, and
# paired-server calls (--environment) refuse it (session_caller_host_boundary).
orca_anon() {
  env -u ORCA_AGENT_SESSION_ID -u ORCA_TERMINAL_HANDLE -u ORCA_AGENT_SESSION_SPAWN_TOKEN \
    -u ORCA_STRUCTURED_SESSION "$ORCA" "$@"
}

# Every worker in a run, on every machine, one JSON object per line, from Orca's worker
# accounting (worker-list --include-remote, every page). A lead on another machine is
# accounted for here too: the Orca coordinating the run records it. terminalState: active
# (closes when it finishes), retained (kept open), release_pending, released, or missing
# when Orca has no terminal for it. Exit 1 if Orca couldn't list the run.
run_workers() {  # run_workers <run>
  python3 - "$ORCA" "$1" <<'PY'
import json, os, subprocess, sys
orca, run = sys.argv[1:3]
env = {k: v for k, v in os.environ.items() if k not in (
    "ORCA_AGENT_SESSION_ID", "ORCA_TERMINAL_HANDLE", "ORCA_AGENT_SESSION_SPAWN_TOKEN",
    "ORCA_STRUCTURED_SESSION")}
cursor, seen, got = None, set(), False
for _ in range(50):
    args = [orca, "orchestration", "worker-list", "--run", run, "--include-remote",
            "--limit", "100", "--json"] + (["--cursor", cursor] if cursor else [])
    try:
        p = subprocess.run(args, capture_output=True, text=True, env=env, timeout=90)
    except Exception:
        break
    # An unreachable machine makes it exit 1, say ok:false and print a second JSON error
    # document after the listing; the listing still holds every worker it accounted for.
    try:
        d = json.JSONDecoder().raw_decode(p.stdout.lstrip())[0]
    except Exception:
        break
    r = d.get("result") if isinstance(d.get("result"), dict) else {}
    if "workers" not in r:
        break
    got = True
    for w in r["workers"]:
        print(json.dumps(w))
    cursor = r.get("nextCursor")
    if not cursor or cursor in seen:
        break
    seen.add(cursor)
sys.exit(0 if got else 1)
PY
}

# "<dispatch> <terminalState>" for every worker in a run ("-" when Orca has no terminal).
lead_terminal_states() {  # lead_terminal_states <run>
  local w
  w="$(run_workers "$1")" || return 1
  python3 -c '
import json, sys
for l in sys.stdin:
    w = json.loads(l)
    print(w.get("dispatchId"), w.get("terminalState") or "-")' <<<"$w"
}
