#!/usr/bin/env bash
# Tests for chiefofstaff's scripts. Run from anywhere: tests/run.sh
# Offline checks always run. Checks that read live Orca or GitHub state (read-only:
# --dry-run and listings, never takeovers or creations) run when orca and gh work;
# CHIEFOFSTAFF_TESTS_OFFLINE=1 skips them.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); echo "  ok    $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "        $2"; }
skip() { skip=$((skip+1)); echo "  skip  $1"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Offline checks run against a test configuration: two machines, "desktop" (this one) and
# "laptop" (Orca environment "lap"), whatever machine the tests run on.
cat > "$tmp/test.conf" <<'EOF'
OPERATOR_NAME="Sam"
CHIEFOFSTAFF_REL="Code/chiefofstaff"
GITHUB_OWNER="example-owner"
MACHINES=(
  "desktop|desk-host|desktop|desk-ssh"
  "laptop|lap-host|lap|lap-ssh"
)
EOF
real_conf="${CHIEFOFSTAFF_CONFIG:-$here/chiefofstaff.conf}"
export CHIEFOFSTAFF_CONFIG="$tmp/test.conf" CHIEFOFSTAFF_MACHINE=desktop
unset CHIEFOFSTAFF_NOTIFY

echo "syntax"
for f in bin/_common.sh bin/start-chiefofstaff bin/sitrep-ping bin/ensure-project bin/orca-account bin/lead-health bin/ledger-edit bin/usage bin/lead-continue bin/last-chat bin/keep-open bin/open-work bin/install-timers tests/run.sh; do
  bash -n "$f" 2>"$tmp/err" && ok "bash -n $f" || bad "bash -n $f" "$(cat "$tmp/err")"
done
if command -v shellcheck >/dev/null; then
  shellcheck -S error bin/_common.sh bin/start-chiefofstaff bin/sitrep-ping bin/ensure-project bin/lead-health bin/ledger-edit bin/usage bin/lead-continue bin/last-chat bin/keep-open bin/open-work bin/install-timers >"$tmp/sc" 2>&1 \
    && ok "shellcheck (errors)" || bad "shellcheck (errors)" "$(head -20 "$tmp/sc")"
else skip "shellcheck not installed"; fi

echo "configuration"
out="$(bash -c '. bin/_common.sh; echo "$CHIEFOFSTAFF_HOST|${OTHER_HOSTS[*]}|${OTHER_ENVS[*]}|${OTHER_SSHS[*]}|$OPERATOR_NAME|$(machine_field laptop env)"')"
[ "$out" = "desktop|laptop|lap|lap-ssh|Sam|lap" ] && ok "reads machines, the other machines' environments and the operator" || bad "config machines" "got: $out"
out="$(CHIEFOFSTAFF_MACHINE= bash -c 'hostname() { echo lap-host; }; . bin/_common.sh; echo "$CHIEFOFSTAFF_HOST ${OTHER_HOSTS[*]}"' 2>&1)"
[ "$out" = "laptop desktop" ] && ok "finds this machine by hostname" || bad "config hostname match" "got: $out"
out="$(CHIEFOFSTAFF_CONFIG="$tmp/missing.conf" bash -c '. bin/_common.sh; echo loaded' 2>&1)"; rc=$?
{ [ $rc = 4 ] && grep -q 'NOT CONFIGURED' <<<"$out" && grep -q 'Onboarding' <<<"$out"; } \
  && ok "without chiefofstaff.conf: NOT CONFIGURED, pointing at onboarding" || bad "config missing" "rc=$rc $out"
out="$(CHIEFOFSTAFF_MACHINE=nowhere bash -c '. bin/_common.sh; echo loaded' 2>&1)"; rc=$?
{ [ $rc = 4 ] && grep -q "isn't in MACHINES" <<<"$out"; } && ok "refuses a machine that isn't configured" || bad "config unknown machine" "rc=$rc $out"
printf 'MACHINES=("solo|solo-host|solo|solo")\n' > "$tmp/solo.conf"
out="$(CHIEFOFSTAFF_CONFIG="$tmp/solo.conf" CHIEFOFSTAFF_MACHINE=solo bash -c '. bin/_common.sh; echo "$CHIEFOFSTAFF_HOST|${#OTHER_HOSTS[@]}|$OPERATOR_NAME|$CHIEFOFSTAFF_REL"')"
[ "$out" = "solo|0|the operator|Code/chiefofstaff" ] && ok "one machine and defaults work" || bad "config one machine" "got: $out"
for f in chiefofstaff.conf.example; do
  out="$(CHIEFOFSTAFF_CONFIG="$f" CHIEFOFSTAFF_MACHINE=desktop bash -c '. bin/_common.sh; echo "$CHIEFOFSTAFF_HOST ${#OTHER_HOSTS[@]}"')"
  [ "$out" = "desktop 1" ] && ok "$f loads" || bad "$f" "got: $out"
done
for f in templates/ledger.md templates/operator.md; do [ -s "$f" ] && ok "template $f" || bad "missing template $f"; done
out="$(CHIEFOFSTAFF_LEDGER=templates/ledger.md bash -c '. bin/_common.sh; echo "[$(ledger_field Host)][$(ledger_field Run)]"')"
[ "$out" = "[][]" ] && ok "the template ledger has no run yet" || bad "template ledger run" "got: $out"

echo "ledger helpers"
cat > "$tmp/ledger.md" <<'EOF'
# Ledger

## Standing guidance

- something

## Chiefofstaff run

- Host: desktop
- Run: `run_aaaaaaaaaaaa`

## Machines

x
EOF
out="$(CHIEFOFSTAFF_LEDGER="$tmp/ledger.md" bash -c '. bin/_common.sh; echo "$(ledger_field Host) $(ledger_field Run)"')"
[ "$out" = "desktop run_aaaaaaaaaaaa" ] && ok "ledger_field reads Host and Run" || bad "ledger_field" "got: $out"
CHIEFOFSTAFF_LEDGER="$tmp/ledger.md" bash -c '. bin/_common.sh; ledger_set_run laptop run_bbbbbbbbbbbb'
out="$(CHIEFOFSTAFF_LEDGER="$tmp/ledger.md" bash -c '. bin/_common.sh; echo "$(ledger_field Host) $(ledger_field Run)"')"
[ "$out" = "laptop run_bbbbbbbbbbbb" ] && ok "ledger_set_run replaces the section" || bad "ledger_set_run" "got: $out"
grep -q '^## Machines' "$tmp/ledger.md" && grep -q '^- something' "$tmp/ledger.md" \
  && [ "$(grep -c '^## Chiefofstaff run' "$tmp/ledger.md")" = 1 ] \
  && ok "ledger_set_run leaves other sections alone" || bad "ledger_set_run clobbered other sections" "$(cat "$tmp/ledger.md")"
printf '# Ledger\n\n## Machines\n\nx\n' > "$tmp/ledger2.md"
CHIEFOFSTAFF_LEDGER="$tmp/ledger2.md" bash -c '. bin/_common.sh; ledger_set_run desktop run_cccccccccccc'
out="$(CHIEFOFSTAFF_LEDGER="$tmp/ledger2.md" bash -c '. bin/_common.sh; ledger_field Run')"
[ "$out" = run_cccccccccccc ] && ok "ledger_set_run adds a missing section" || bad "ledger_set_run add" "got: $out"

echo "ledger-edit"
cp "$tmp/ledger.md" "$tmp/le.md"
printf '\n## Projects\n\n- **alpha** (started x): one.\n- **beta**: two.\n' >> "$tmp/le.md"
le() { CHIEFOFSTAFF_LEDGER="$tmp/le.md" bin/ledger-edit "$@"; }
le 'one.' 'one, edited.' >/dev/null && grep -q 'alpha\*\* (started x): one, edited\.' "$tmp/le.md" \
  && ok "replaces text that occurs once" || bad "ledger-edit replace"
cp "$tmp/le.md" "$tmp/le.bak"
le 'not there' 'x' 2>"$tmp/err"; rc=$?
{ [ $rc = 1 ] && grep -q 'found 0 times' "$tmp/err" && cmp -s "$tmp/le.md" "$tmp/le.bak"; } \
  && ok "fails loudly and changes nothing when the text is missing" || bad "ledger-edit missing" "rc=$rc"
le '- **' 'x' 2>/dev/null; rc=$?
{ [ $rc = 1 ] && cmp -s "$tmp/le.md" "$tmp/le.bak"; } && ok "refuses ambiguous text" || bad "ledger-edit ambiguous" "rc=$rc"
le --append beta 'Three.' >/dev/null && grep -qx -- '- \*\*beta\*\*: two. Three.' "$tmp/le.md" \
  && ok "--append adds to a project's entry" || bad "ledger-edit --append" "$(grep beta "$tmp/le.md")"
le --append gamma 'x' 2>/dev/null; [ $? = 1 ] && ok "--append fails for an unknown project" || bad "--append unknown project"
le --append beta 'Four.' >/dev/null 2>"$tmp/err" && [ ! -s "$tmp/err" ] && ok "no length warning for a short entry" || bad "ledger-edit warned on a short entry" "$(cat "$tmp/err")"
LEDGER_ENTRY_WORDS=7 le --append beta 'Five six seven.' >/dev/null 2>"$tmp/err"; rc=$?
{ [ $rc = 0 ] && grep -q 'entries over 7 words' "$tmp/err" && grep -q '^  beta: ' "$tmp/err" && ! grep -q alpha "$tmp/err"; } \
  && ok "warns when an edit leaves an entry over the limit" || bad "ledger-edit length warning" "rc=$rc $(cat "$tmp/err")"
out="$(CHIEFOFSTAFF_LEDGER="$tmp/le.md" LEDGER_ENTRY_WORDS=7 bash -c '. bin/_common.sh; ledger_long_entries')"
grep -qx "beta: [0-9]* words" <<<"$out" && ok "ledger_long_entries lists only long project entries" || bad "ledger_long_entries" "got: $out"

echo "last-chat"
tr="$tmp/transcripts"; mkdir -p "$tr"
jl() { python3 -c 'import json,sys; [print(json.dumps(json.loads(l))) for l in sys.argv[1:]]' "$@"; }
jl '{"type":"user","timestamp":"2026-11-08T20:00:00Z","message":{"content":"Where is webapp at?"}}' \
   '{"type":"assistant","timestamp":"2026-11-08T20:00:05Z","message":{"content":[{"type":"text","text":"Blocked on you: 1. webapp: A or B?"}]}}' \
   '{"type":"user","timestamp":"2026-11-08T20:01:00Z","message":{"content":[{"type":"tool_result","content":"x"}]}}' \
   '{"type":"user","timestamp":"2026-11-08T20:02:00Z","message":{"content":"──── From: dispatch:ctx_1 (question) ────"}}' \
   '{"type":"assistant","timestamp":"2026-11-08T20:03:00Z","isSidechain":true,"message":{"content":[{"type":"text","text":"subagent noise"}]}}' \
   > "$tr/old-session.jsonl"
jl '{"type":"user","timestamp":"2026-11-08T21:00:00Z","message":{"content":"start"}}' > "$tr/cur-session.jsonl"
python3 -c 'import os,sys,time; t=time.time()-3600; os.utime(sys.argv[1], (t, t))' "$tr/old-session.jsonl"
out="$(CHIEFOFSTAFF_TRANSCRIPTS="$tr" CLAUDE_CODE_SESSION_ID=cur-session bin/last-chat)"
{ grep -q 'Previous chat on .*: old-sess' <<<"$out" && grep -q 'Where is webapp at' <<<"$out" \
  && grep -q "Sam's last message" <<<"$out" && grep -q '1. webapp: A or B' <<<"$out" && ! grep -q 'From: dispatch\|subagent noise' <<<"$out"; } \
  && ok "shows the previous chat's last exchange, skipping this session and noise" || bad "last-chat" "$out"
out="$(CHIEFOFSTAFF_TRANSCRIPTS="$tmp/none" bin/last-chat)"
grep -q 'no chiefofstaff transcripts' <<<"$out" && ok "says so when there are no transcripts" || bad "last-chat empty" "$out"

# A fake orca for lead-health and sitrep-ping: answers from $FAKE/<command>.json (or
# <command>-<environment>.json), records sends in $FAKE/sent.
FAKE="$tmp/fake"; mkdir -p "$FAKE"; export FAKE
cat > "$tmp/fake-orca" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]; f = os.environ["FAKE"]
cmd = a[1] if len(a) > 1 else ""
if cmd == "send":
    if os.path.exists(f + "/fail-send"): sys.exit(1)
    open(f + "/sent", "a").write(json.dumps(a) + "\n"); print('{"ok":true}'); sys.exit()
if cmd == "worker-read" and "--cursor" in a:
    p = f"{f}/worker-read-next.json"
    print(open(p).read() if os.path.exists(p) else '{"ok":true,"result":{"transcript":{"messages":[]}}}'); sys.exit()
env = a[a.index("--environment") + 1] if "--environment" in a else ""
key = cmd + ("-" + a[a.index("--dispatch") + 1] if "--dispatch" in a else "") + ("-" + env if env else "")
p = f"{f}/{key}.json"
if not os.path.exists(p):
    print(json.dumps({"ok": False, "error": {"code": "not_found", "message": key}})); sys.exit(1)
print(open(p).read())
EOF
chmod +x "$tmp/fake-orca"
fj() { printf '%s' "$2" > "$FAKE/$1.json"; }
now_ms=$(( $(date +%s) * 1000 ))
fj task-list '{"ok":true,"result":{"tasks":[
 {"id":"t1","status":"dispatched","title":"local-ok","dispatchId":"ctx_local"},
 {"id":"t2","status":"dispatched","title":"remote-broken","dispatchId":"ctx_remote"},
  {"id":"t3","status":"completed","title":"done"}]}}' 
fj worker-show-ctx_local '{"ok":true,"result":{"observation":{"status":"live","exactWorker":true}}}'
fj worker-read-ctx_local "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$now_ms}]}}}"
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"identity_changed"}}}'
fj inbox '{"ok":true,"result":[]}'
other_env=lap
fj inbox-lap '{"ok":true,"result":[]}'
lh() { CHIEFOFSTAFF_STATE_DIR="$tmp/state" CHIEFOFSTAFF_LEDGER="$tmp/ledger4.md" ORCA="$tmp/fake-orca" bin/lead-health "$@"; }
printf '## Chiefofstaff run\n\n- Host: desktop\n- Run: `run_dddddddddddd`\n\n## Machines\n' > "$tmp/ledger4.md"

echo "lead-health"
out="$(lh)"; rc=$?
{ [ $rc = 1 ] && grep -q 'ok .*local-ok' <<<"$out" && grep -q 'STALLED .*remote-broken.*on lap' <<<"$out" \
  && grep -q 'identity_changed' <<<"$out" && ! grep -q 'done' <<<"$out"; } \
  && ok "flags a remote lead Orca can't see, passes a live one, skips finished tasks" || bad "lead-health verdicts" "rc=$rc $out"
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"live"}}}'
out="$(lh)"; rc=$?
[ $rc = 0 ] && ok "all ok exits 0" || bad "lead-health all ok" "rc=$rc $out"
fj inbox-lap '{"ok":true,"result":[{"id":"m1","type":"status","to":"dispatch:ctx_remote","handled":false,"subject":"hi"}]}'
out="$(LEAD_HEALTH_MAIL_MIN=0 lh)"; rc=$?
{ [ $rc = 1 ] && grep -q "unread .* in lap's inbox" <<<"$out"; } \
  && ok "flags mail a remote lead never picked up" || bad "lead-health undelivered mail" "rc=$rc $out"
out="$(lh)"; rc=$?
[ $rc = 0 ] && ok "doesn't flag mail before it has waited MAIL_MIN" || bad "lead-health mail threshold" "rc=$rc $out"
# Unread mail to a lead that is still producing output isn't a stall; once its output stops
# for MAIL_MIN it is, even though it produced output after the mail arrived.
fj inbox '{"ok":true,"result":[{"id":"m2","type":"status","to":"dispatch:ctx_local","handled":false,"subject":"hi"}]}'
python3 - "$tmp/state/lead-health.json" <<'EOF'
import json, sys, time
p = sys.argv[1]; s = json.load(open(p)); s["seen"]["m2"] = time.time() - 3600; json.dump(s, open(p, "w"))
EOF
out="$(LEAD_HEALTH_MAIL_MIN=15 lh)"; rc=$?
[ $rc = 0 ] && ok "busy lead with unread mail is ok" || bad "lead-health flagged a busy lead" "rc=$rc $out"
old_ms=$(( ($(date +%s) - 1800) * 1000 ))
fj worker-read-ctx_local "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$old_ms}]}}}"
out="$(LEAD_HEALTH_MAIL_MIN=15 lh)"; rc=$?
{ [ $rc = 1 ] && grep -q 'local-ok' <<<"$out" && grep -q "unread" <<<"$out"; } \
  && ok "lead that went quiet after the mail arrived is flagged" || bad "lead-health missed a lead that went quiet" "rc=$rc $out"
fj worker-read-ctx_local "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$old_ms}],\"nextCursor\":\"c1\"}}}"
fj worker-read-next "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$now_ms}]}}}"
out="$(LEAD_HEALTH_MAIL_MIN=15 lh)"; rc=$?
{ [ $rc = 0 ] && grep -q 'local-ok.*(0 min ago)' <<<"$out"; } \
  && ok "reads a lead's newest output across worker-read pages" || bad "lead-health read a stale page" "rc=$rc $out"
rm "$FAKE/worker-read-next.json"
fj worker-read-ctx_local "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$now_ms}]}}}"
fj inbox '{"ok":true,"result":[]}'
rm "$FAKE/inbox-lap.json"
out="$(lh)"; rc=$?
{ [ $rc = 1 ] && grep -q "can't read lap's inbox" <<<"$out"; } \
  && ok "flags a remote lead whose mail can't be checked" || bad "lead-health remote inbox" "rc=$rc $out"
fj inbox-lap '{"ok":true,"result":[]}'
fj worker-show-ctx_local '{"ok":true,"result":{"observation":{"status":"live","agentWait":{"kind":"permission","evidence":"hook"}}}}'
out="$(lh)"; rc=$?
{ [ $rc = 1 ] && grep -q 'parked on a prompt' <<<"$out"; } && ok "flags a lead parked on a prompt" || bad "lead-health agentWait" "rc=$rc $out"
fj worker-show-ctx_local '{"ok":true,"result":{"observation":{"status":"live","exactWorker":true}}}'
fj inbox '{"ok":true,"result":[{"id":"q1","type":"question","to":"run:run_dddddddddddd","handled":false,"subject":"Which?"}]}'
out="$(LEAD_HEALTH_CHIEFOFSTAFF_MIN=0 lh)"; rc=$?
{ [ $rc = 1 ] && grep -q "chiefofstaff hasn't handled" <<<"$out" && grep -q 'q1' <<<"$out"; } \
  && ok "flags lead reports chiefofstaff hasn't handled" || bad "lead-health chiefofstaff behind" "rc=$rc $out"
fj inbox '{"ok":true,"result":[]}'
# Why a quiet ok lead is quiet: its last words, or an open question of its own.
said() { fj worker-read-ctx_local "{\"ok\":true,\"result\":{\"transcript\":{\"messages\":[{\"timestamp\":$1,\"role\":\"assistant\",\"blocks\":[{\"type\":\"text\",\"text\":\"$2\"}]},{\"timestamp\":$1,\"role\":\"system\",\"blocks\":[{\"type\":\"text\",\"text\":\"claude · vcs\"}]}]}}}"; }
said "$old_ms" "Started the builder for #31. Ending my turn until it reports back."
out="$(lh)"; rc=$?
{ [ $rc = 0 ] && grep -q 'local-ok.*; waiting$' <<<"$out" && grep -q 'said: "Started the builder' <<<"$out"; } \
  && ok "quiet lead waiting on its worker is 'waiting', with its last words" || bad "lead-health waiting verdict" "rc=$rc $out"
said "$old_ms" "All done, merged PR 12."
out="$(lh)"; rc=$?
{ [ $rc = 0 ] && grep -q 'local-ok.*; idle (ended its turn' <<<"$out"; } \
  && ok "quiet lead that waits on nothing is 'idle'" || bad "lead-health idle verdict" "rc=$rc $out"
said "$old_ms" "I am not waiting for a worker; the build is stuck."
out="$(lh)"; grep -q 'local-ok.*; idle' <<<"$out" && ok "'not waiting' or 'stuck' is idle, not waiting" || bad "lead-health negation" "$out"
said "$old_ms" "Sent the plan; waiting for Sam to choose."
out="$(lh)"; grep -q 'local-ok.*; waiting$' <<<"$out" && ok "waiting on the operator by name is 'waiting'" || bad "lead-health operator name" "$out"
fj inbox '{"ok":true,"result":[{"id":"q2","type":"question","from":"ctx_local","to":"run:run_dddddddddddd","handled":false,"subject":"A or B?"}]}'
out="$(lh)"; rc=$?
grep -q 'local-ok.*; waiting on its question' <<<"$out" \
  && ok "quiet lead with an open question is waiting on it" || bad "lead-health question verdict" "rc=$rc $out"
fj inbox '{"ok":true,"result":[]}'
said "$now_ms" "All done, merged PR 12."
out="$(lh)"; rc=$?
{ [ $rc = 0 ] && ! grep -q 'local-ok.*; \(idle\|waiting\)' <<<"$out"; } \
  && ok "a lead with recent output gets no verdict" || bad "lead-health verdict on a busy lead" "rc=$rc $out"
# Mail to a finished lead never arrives; flagged with the way to resend it.
fj inbox '{"ok":true,"result":[{"id":"m9","type":"status","to":"dispatch:ctx_done","handled":false,"subject":"Re: your report"}]}'
fj worker-show-ctx_done '{"ok":true,"result":{"dispatch":{"runId":"run_dddddddddddd","taskId":"t3","status":"completed"},"server":{"name":"lap"},"worker":{"state":"succeeded","agentTerminalHandle":"term_abc","worktreeId":"r1::/Users/user/orca/workspaces/notes app/docs"}}}'
out="$(lh)"; rc=$?
{ [ $rc = 1 ] && grep -q 'UNSENT .*m9.*finished lead done.*bin/lead-continue ctx_done' <<<"$out"; } \
  && ok "flags mail to a finished lead, with lead-continue" || bad "lead-health finished-lead mail" "rc=$rc $out"
python3 - "$tmp/state/lead-health.json" <<'EOF'
import json, sys, time
p = sys.argv[1]; s = json.load(open(p)); s["seen"]["m9"] = time.time() - 25 * 3600; json.dump(s, open(p, "w"))
EOF
out="$(lh)"; rc=$?
[ $rc = 0 ] && ok "stops flagging finished-lead mail after a day" || bad "lead-health finished-lead mail expiry" "rc=$rc $out"
fj inbox '{"ok":true,"result":[]}'

echo "lead-continue"
lc() { CHIEFOFSTAFF_LEDGER="$tmp/ledger4.md" ORCA="$tmp/fake-orca" bin/lead-continue "$@"; }
fj worker-show-ctx_done '{"ok":true,"result":{"server":{"name":"lap"},"worker":{"agentTerminalHandle":"term_abc","worktreeId":"r1::/Users/user/orca/workspaces/notes app/docs"}}}'
out="$(lc ctx_done --spec-file f.md --title 'docs: more' --dry-run)"
{ grep -q -- '--terminal term_abc' <<<"$out" && grep -q -- '--worktree id:r1::/Users/user/orca/workspaces/notes\\ app/docs' <<<"$out" \
  && grep -q -- '--on lap' <<<"$out" && grep -q -- '--run run_dddddddddddd' <<<"$out" && grep -q -- '--spec-file f.md' <<<"$out"; } \
  && ok "continues a finished remote lead in its own chat" || bad "lead-continue remote" "$out"
fj worker-show-ctx_local '{"ok":true,"result":{"worker":{"agentTerminalHandle":"structworker_1","worktreeId":"r2::/home/user/w"}}}'
out="$(lc ctx_local --spec hi --dry-run)"
{ grep -q -- '--terminal structworker_1 --worktree id:r2::/home/user/w' <<<"$out" && ! grep -q -- '--on' <<<"$out"; } \
  && ok "continues a local lead without --on" || bad "lead-continue local" "$out"
out="$(lc --terminal term_x --worktree id:r3::/p --on lap --spec hi --dry-run)"
grep -q -- '--terminal term_x --worktree id:r3::/p --keep-open --spec hi --on lap' <<<"$out" && ok "adopts any chat by terminal and workspace, kept open" || bad "lead-continue adopt" "$out"
lc ctx_ffffffffffff --spec hi --dry-run 2>"$tmp/err"; rc=$?
{ [ $rc = 1 ] && grep -q "can't show dispatch" "$tmp/err"; } && ok "fails clearly for an unknown dispatch" || bad "lead-continue unknown" "rc=$rc"
lc ctx_done --dry-run 2>/dev/null; [ $? = 2 ] && ok "needs a spec" || bad "lead-continue without spec"
out="$(lc ctx_local --spec hi --dry-run)"; grep -q -- ' --keep-open ' <<<"$out" && ok "starts follow-ups with --keep-open" || bad "lead-continue keep-open" "$out"

echo "keep-open"
fj worker-list '{"ok":false,"result":{"workers":[
 {"dispatchId":"ctx_kept","terminal":"structworker_9","terminalState":"retained","outcome":"in_progress","workspace":"w1"},
 {"dispatchId":"ctx_dead","terminal":"term_dead","terminalState":"retained","workspace":"w2"},
 {"dispatchId":"ctx_closing","terminal":"term_live","terminalState":"active","outcome":"in_progress","workspace":"w2"},
 {"dispatchId":"ctx_gone","workspace":"w2"}]}}
{"ok":false,"error":{"code":"worker_inventory_incomplete"}}'
fj worker-show-ctx_kept '{"ok":true,"result":{"worker":{"agentTerminalHandle":"structworker_9"}}}'
fj worker-show-ctx_dead '{"ok":true,"result":{"server":{"name":"lap"},"worker":{"agentTerminalHandle":"term_dead"}}}'
fj show-lap '{"ok":true,"result":{"terminal":{"handle":"term_dead","connected":false}}}'
for d in kept dead closing gone; do fj worker-keep-open-ctx_$d '{"ok":true,"result":{"state":"retained"}}'; done
ko() { CHIEFOFSTAFF_LEDGER="$tmp/ledger4.md" ORCA="$tmp/fake-orca" bin/keep-open "$@"; }
out="$(ko ctx_kept)"; rc=$?
{ [ $rc = 0 ] && grep -qx 'ctx_kept: kept open' <<<"$out"; } && ok "confirms a retained lead, even when a machine was unreachable" || bad "keep-open retained" "rc=$rc $out"
out="$(ko ctx_dead ctx_closing ctx_gone ctx_unknown)"; rc=$?
{ [ $rc = 1 ] && grep -q '^ctx_dead: already closed .*term_dead is gone' <<<"$out" \
  && grep -q '^ctx_closing: NOT kept open: .* as active' <<<"$out" \
  && grep -q '^ctx_gone: already closed (Orca has no terminal' <<<"$out" \
  && grep -q "^ctx_unknown: NOT kept open: Orca doesn't list it" <<<"$out"; } \
  && ok "reports a closed terminal, a lead that will close, and unknown dispatches" || bad "keep-open verdicts" "rc=$rc $out"
rm -f "$FAKE/show-lap.json"
out="$(ko ctx_dead)"; rc=$?
{ [ $rc = 1 ] && grep -q "^ctx_dead: kept open in Orca's record, but its terminal term_dead couldn't be checked on lap" <<<"$out"; } \
  && ok "doesn't confirm a lead whose terminal it couldn't check" || bad "keep-open unchecked" "rc=$rc $out"
ko >/dev/null 2>&1; [ $? = 2 ] && ok "needs a dispatch" || bad "keep-open without args"

cat > "$tmp/paged-orca" <<'PAGED'
#!/usr/bin/env bash
case " $* " in
  *" --cursor c2 "*) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_p2","terminalState":"retained"}]}}' ;;
  *) echo '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_p1","terminalState":"active"}],"nextCursor":"c2"}}' ;;
esac
PAGED
chmod +x "$tmp/paged-orca"
out="$(ORCA="$tmp/paged-orca" bash -c '. bin/_common.sh; lead_terminal_states run_x')"
[ "$out" = "$(printf 'ctx_p1 active\nctx_p2 retained')" ] && ok "reads every page of Orca's worker list" || bad "run_workers paging" "$out"

echo "lead-health keep-open"
fj worker-show-ctx_local '{"ok":true,"result":{"observation":{"status":"live","exactWorker":true}}}'
fj worker-list '{"ok":true,"result":{"workers":[{"dispatchId":"ctx_local","terminal":"structworker_1","terminalState":"active","outcome":"in_progress"}]}}'
fj worker-keep-open-ctx_local '{"ok":true,"result":{"state":"retained"}}'
out="$(lh)"; grep -q 'ok .*local-ok.*kept open now' <<<"$out" && ok "keeps open an active lead Orca would close" || bad "lead-health keep-open" "$out"
rm -f "$FAKE/worker-keep-open-ctx_local.json"
out="$(lh)"; grep -q 'STALLED .*local-ok' <<<"$out" && grep -q 'worker-keep-open failed' <<<"$out" \
  && ok "flags a lead it can't keep open" || bad "lead-health keep-open failure" "$out"
rm -f "$FAKE/worker-list.json"; rm -rf "$tmp/state"

echo "open-work"
day=86400000
fj worker-list '{"ok":true,"result":{"workers":[
 {"dispatchId":"ctx_new","terminal":"term_docs","terminalState":"retained","outcome":"in_progress","workspace":"r9::/Users/user/docs"},
 {"dispatchId":"ctx_old","terminal":"term_docs","terminalState":"retained","workspace":"r9::/Users/user/docs"},
 {"dispatchId":"ctx_closed","terminal":"term_x","terminalState":"retained","workspace":"r1::/home/user/a"}]}}'
fj ps "{\"ok\":true,\"result\":{\"worktrees\":[
 {\"worktreeId\":\"r1::/home/user/a\",\"repo\":\"api\",\"displayName\":\"a\",\"branch\":\"refs/heads/sam/a\",\"linkedPR\":{\"number\":7,\"state\":\"merged\"},\"lastActivityAt\":$((now_ms - 2*day)),\"agents\":[{\"state\":\"done\",\"displayName\":\"api: fix a\"}]},
 {\"worktreeId\":\"r1::/home/user/b\",\"repo\":\"api\",\"displayName\":\"b\",\"lastActivityAt\":$now_ms,\"agents\":[{\"state\":\"working\",\"displayName\":\"busy\"}]},
 {\"worktreeId\":\"r1::/home/user/api\",\"repo\":\"api\",\"displayName\":\"main\",\"isMainWorktree\":true,\"agents\":[{\"state\":\"done\"}]},
 {\"worktreeId\":\"r2::/home/user/x\",\"repo\":\"x\",\"displayName\":\"main\",\"isMainWorktree\":true,\"agents\":[]}]}}"
fj "ps-$other_env" "{\"ok\":true,\"result\":{\"worktrees\":[
 {\"worktreeId\":\"r9::/Users/user/docs\",\"repo\":\"notes app\",\"displayName\":\"docs\",\"lastActivityAt\":$((now_ms - 20*day)),\"agents\":[{\"state\":\"done\"}]}]}}"
fj list '{"ok":true,"result":{"terminals":[]}}'
fj "list-$other_env" '{"ok":true,"result":{"terminals":[{"handle":"term_docs","connected":true}]}}'
ow() { CHIEFOFSTAFF_LEDGER="$tmp/ledger4.md" ORCA="$tmp/fake-orca" bin/open-work; }
out="$(ow)"
{ grep -q '^  close? api/a (sam/a); PR #7 merged; idle 2 d; 1 chat (1 done): "api: fix a"$' <<<"$out" \
  && grep -q '^  api/b; active today; 1 chat (1 working): "busy"$' <<<"$out" \
  && grep -q 'main checkouts with chats: api/main (1 chat)$' <<<"$out" && ! grep -q 'x/main' <<<"$out"; } \
  && ok "lists workspaces and chats, marks likely candidates, skips quiet main checkouts" || bad "open-work list" "$out"
{ grep -q 'notes app/docs; idle 20 d; 1 chat (1 done); chiefofstaff lead ctx_new (active, kept open)$' <<<"$out" \
  && ! grep -q 'ctx_old\|ctx_closed' <<<"$out"; } \
  && ok "shows the newest lead per chat, drops kept-open records whose terminal is gone" || bad "open-work leads" "$out"
rm -f "$FAKE/ps-$other_env.json"
out="$(ow)"; grep -q "can't list workspaces" <<<"$out" && grep -q 'api/a' <<<"$out" \
  && ok "says when a machine can't be listed, still lists the other" || bad "open-work unreachable" "$out"
fj worker-show-ctx_local '{"ok":true,"result":{"observation":{"status":"live","exactWorker":true}}}'

echo "ensure-project (offline)"
mkdir -p "$tmp/bin-gh" "$tmp/proj"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin-gh/gh"; chmod +x "$tmp/bin-gh/gh"
git -C "$tmp/proj" init -q -b main && git -C "$tmp/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "$tmp/proj" remote add origin git@github.com:example-owner/zz-proj.git
fj setups '{"ok":true,"result":{"setups":[]}}'
PATH="$tmp/bin-gh:$PATH" ORCA="$tmp/fake-orca" bin/ensure-project zz-proj --path "$tmp/proj" >"$tmp/out" 2>"$tmp/err"; rc=$?
{ [ $rc = 1 ] && grep -q 'Orca refused to add' "$tmp/err" && grep -q 'not_found' "$tmp/err"; } \
  && ok "reports Orca's refusal instead of exiting silently" || bad "ensure-project silent failure" "rc=$rc $(cat "$tmp/err")"
rm "$FAKE/setups.json"

echo "usage"
# Snapshots as bin/_usage.js dump writes them; NOW is fixed. H = 1 hour in ms.
NOW=1800000000000; H=3600000
mkusage() {  # mkusage <dir> <desktop claude work week%> <work week hours left> <personal week%> <personal hours left> [<desktop active: work|personal>]
  mkdir -p "$1"; rm -f "$1"/*.json
  local act="${6:-work}"
  python3 - "$1" "$NOW" "$H" "$2" "$3" "$4" "$5" "$act" <<'PY'
import json, sys
d, now, H, ww, wl, nw, nl, act = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), *map(float, sys.argv[4:8]), sys.argv[8]
def acct(i, email, active, week, hours, five=10):
    return {"id": i, "key": email, "email": email, "active": active, "status": "ok", "error": None,
            "updatedAt": now - 60000, "extra": None,
            "windows": [{"minutes": 300, "used": five, "resetsAt": now + 2 * H},
                        {"minutes": 10080, "used": week, "resetsAt": now + int(hours * H)}]}
lin = {"host": "desktop", "ok": True,
       "claude": {"accounts": [acct("w1", "work@x", act == "work", ww, wl), acct("n1", "personal@x", act == "personal", nw, nl)]},
       "codex": {"accounts": [acct("c1", "work@x", True, 20, 100)]}}
mac = {"host": "laptop", "ok": False, "error": "Orca did not answer"}
json.dump(lin, open(f"{d}/a.json", "w")); json.dump(mac, open(f"{d}/b.json", "w"))
PY
}
U="$tmp/usage"
us() { CHIEFOFSTAFF_USAGE_FIXTURE="$U" CHIEFOFSTAFF_NOW_MS=$NOW CHIEFOFSTAFF_STATE_DIR="$tmp/ustate" bin/usage "$@"; }
mkusage "$U" 90 2 10 100
out="$(us)"; grep -q 'week 90%, resets in 2.0h, on pace' <<<"$out" && ok "90% with 2h left is on pace" || bad "usage pace 2h" "$out"
mkusage "$U" 90 120 10 100
out="$(us)"; grep -qE 'week 90%, resets in 5d0h, ahead of pace by 61 pts' <<<"$out" && ok "90% with 5 days left is far ahead of pace" || bad "usage pace 5d" "$out"
mkusage "$U" 20 80 20 80
out="$(us)"; grep -q 'Claude tier: normal' <<<"$out" && ok "tier normal when on pace" || bad "tier normal" "$out"
mkusage "$U" 70 120 70 120
out="$(us)"; grep -q 'Claude tier: conserve' <<<"$out" && ok "tier conserve when far ahead across accounts" || bad "tier conserve" "$out"
mkusage "$U" 100 120 100 100
out="$(us)"; grep -q 'Claude tier: exhausted' <<<"$out" && ok "tier exhausted when every account is at a limit" || bad "tier exhausted" "$out"
grep -q 'Not read: laptop' <<<"$out" && ok "reports an unreachable machine and still reports this one" || bad "usage unreachable" "$out"
mkusage "$U" 92 50 30 100
out="$(us)"; grep -q 'Switch claude on desktop: work@x is at 92%.*bin/orca-account claude n1' <<<"$out" \
  && ok "advises a switch when the active account is near its limit" || bad "usage switch" "$out"
mkusage "$U" 92 50 95 100
out="$(us)"; grep -q 'no other claude account has room' <<<"$out" && ok "says when no account has room" || bad "usage no room" "$out"
us --json | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["tier"] and r["kinds"]["claude"]' \
  && ok "--json is valid JSON" || bad "usage --json"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80
[ -z "$(us --watch)" ] && ok "watch: silent when normal" || bad "usage watch noisy"
mkusage "$U" 92 50 30 100
[ -n "$(us --watch)" ] && ok "watch: alerts on a new switch advice" || bad "usage watch missed switch"
us --ack; [ -z "$(us --watch)" ] && ok "watch: doesn't repeat after --ack" || bad "usage watch repeated"
mkusage "$U" 92 50 30 100; [ -n "$(us --watch)" ] || true
mkusage "$U" 70 120 70 120
[ -n "$(us --watch)" ] && ok "watch: alerts when the tier worsens" || bad "usage watch missed tier"
mkusage "$U" 92 50 30 100; rm -rf "$tmp/ustate"; us --watch >/dev/null
[ -n "$(us --watch)" ] && ok "watch: repeats until acknowledged (a failed send retries)" || bad "usage watch lost unacked alert"
mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
mkusage "$U" 92 50 30 100
[ -n "$(us --watch)" ] && ok "watch: alerts again after it clears and returns" || bad "usage watch no re-alert"
mkusage "$U" 92 50 30 100; us --watch >/dev/null; us --ack
python3 - "$U/a.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["ok"] = False; d["error"] = "down"; json.dump(d, open(sys.argv[1], "w"))
PY
out="$(us)"; grep -q 'Claude tier: unknown' <<<"$out" && ok "tier unknown when nothing could be read" || bad "usage unknown" "$out"
[ -z "$(us --watch)" ] && ok "watch: an outage neither alerts nor clears the alert state" || bad "usage watch on outage"
mkusage "$U" 92 50 30 100; [ -z "$(us --watch)" ] && ok "watch: no repeat after the outage ends" || bad "usage watch repeated after outage"
mkusage "$U" 20 -1 97 100
out="$(us)"; grep -q 'week reset since the last reading' <<<"$out" && grep -q 'Claude tier: critical' <<<"$out" \
  && ok "an expired window adds no budget to the tier" || bad "usage expired window" "$out"
mkusage "$U" 100 50 100 100
python3 - "$U/a.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1]))
d["claude"]["accounts"].append({"id": "x1", "key": "x@x", "email": "x@x", "active": False, "status": "error", "error": "stale-token", "updatedAt": 0, "extra": None, "windows": []})
json.dump(d, open(sys.argv[1], "w"))
PY
out="$(us)"; grep -q 'Claude tier: critical' <<<"$out" && ok "not exhausted while an account has no reading" || bad "usage exhausted with unknown" "$out"
mkusage "$U" 20 80 20 80

# Threshold notices (80% and 90% of any window of an account in use)
setwin() {  # setwin <kind> <email> <minutes> <used> [<hours to reset> [<extra ms>]]: edit the fixture's window
  python3 - "$U/a.json" "$NOW" "$H" "$@" <<'PY'
import json, sys
f, now, H, kind, email, minutes, used = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5], int(sys.argv[6]), float(sys.argv[7])
d = json.load(open(f))
for a in d[kind]["accounts"]:
    if a["email"] == email:
        for w in a["windows"]:
            if w["minutes"] == minutes:
                w["used"] = used
                if len(sys.argv) > 8: w["resetsAt"] = now + int(float(sys.argv[8]) * H) + (int(sys.argv[9]) if len(sys.argv) > 9 else 0)
json.dump(d, open(f, "w"))
PY
}
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80
us --watch >/dev/null; us --ack
setwin claude work@x 300 82 1.5
out="$(us --watch)"
[ "$(grep -c '^Threshold: ' <<<"$out")" = 1 ] && head -1 <<<"$out" | grep -q '^Threshold: claude work@x (active on desktop) is at 82% of its 5h window, resets in 1.5h\.$' \
  && ok "threshold: 80% prints one line with kind, account, machine, window, percent and reset" || bad "threshold 80" "$out"
grep -q 'Claude tier:' <<<"$out" && ok "threshold: the full report follows the lines" || bad "threshold report" "$out"
grep -q 'will switch\|has room' <<<"$(grep '^Threshold' <<<"$out")" && bad "threshold: 80% must not mention a switch" "$out" || ok "threshold: 80% has no switch note"
us --ack; [ -z "$(us --watch)" ] && ok "threshold: not repeated after --ack" || bad "threshold repeated"
setwin claude work@x 300 83 1.5; [ -z "$(us --watch)" ] && ok "threshold: still 80% in the same period stays quiet" || bad "threshold 80 re-alert"
setwin claude work@x 300 91 1.4
out="$(us --watch)"
[ "$(grep -c '^Threshold: ' <<<"$out")" = 1 ] && grep -q '^Threshold: claude work@x .* is at 91% of its 5h window, resets in 1.4h\. chiefofstaff will switch claude on desktop to personal@x\.$' <<<"$out" \
  && ok "threshold: 90% prints once, naming the switch chiefofstaff will make" || bad "threshold 90" "$out"
us --ack
setwin claude work@x 300 85 1.4; [ -z "$(us --watch)" ] && ok "threshold: 80% is implied once 90% was sent" || bad "threshold 80 after 90"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 93 1.5
out="$(us --watch)"
{ [ "$(grep -c '^Threshold: ' <<<"$out")" = 1 ] && grep -q 'is at 93%' <<<"$out"; } && ok "threshold: a jump past 90% sends only the 90% line" || bad "threshold jump" "$out"
us --ack
setwin claude work@x 300 84 2.9
out="$(us --watch)"; grep -q '^Threshold: claude work@x .* is at 84%' <<<"$out" \
  && ok "threshold: a new reset time notifies again" || bad "threshold new period" "$out"
us --ack
python3 - "$tmp/ustate/usage.json" "$NOW" <<'PYEOF'
import json, sys
f, now = sys.argv[1], int(sys.argv[2]); d = json.load(open(f))
d["alerted"]["thresholds"].append({"kind": "claude", "email": "old@x", "minutes": 300, "resetsAt": now - 1, "threshold": 80})
json.dump(d, open(f, "w"))
PYEOF
us --watch >/dev/null; us --ack
python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["alerted"]["thresholds"]; assert sorted(e["email"] for e in a)==["work@x","work@x"], a' "$tmp/ustate/usage.json" \
  && ok "threshold: entries whose period is over (reset time past) are pruned" || bad "threshold prune" "$(cat "$tmp/ustate/usage.json")"
# Reset-time jitter, missing readings, unknown tier, no room to switch
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 82 1.5; us --watch >/dev/null; us --ack
setwin claude work@x 300 82 1.5 700; [ -z "$(us --watch)" ] && ok "threshold: reset-time jitter (+700ms) is the same period" || bad "threshold jitter"
setwin claude work@x 300 82 1.5 -400; [ -z "$(us --watch)" ] && ok "threshold: jitter in the other direction is the same period" || bad "threshold jitter -"
setwin claude work@x 300 82 6.5; [ -n "$(us --watch)" ] && ok "threshold: a window 5h later is a new period" || bad "threshold next window"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 82 1.5; us --watch >/dev/null; us --ack
python3 - "$U/a.json" <<'PYEOF'
import json, sys; f = sys.argv[1]; d = json.load(open(f))
json.dump(d, open(f + ".full", "w")); d["claude"]["accounts"] = [a for a in d["claude"]["accounts"] if a["email"] != "work@x"]; json.dump(d, open(f, "w"))
PYEOF
us --watch >/dev/null; us --ack; cp "$U/a.json.full" "$U/a.json"; rm "$U/a.json.full"
[ -z "$(us --watch)" ] && ok "threshold: a missing account reading doesn't erase history" || bad "threshold history lost"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
python3 - "$U/a.json" <<'PYEOF'
import json, sys; f = sys.argv[1]; d = json.load(open(f))
for a in d["claude"]["accounts"]: a["windows"] = [w for w in a["windows"] if w["minutes"] != 10080]
json.dump(d, open(f, "w"))
PYEOF
setwin codex work@x 300 91
out="$(us --watch)"; grep -q 'Claude tier: unknown' <<<"$out" && grep -q '^Threshold: codex work@x .* is at 91% of its 5h window' <<<"$out" \
  && ok "threshold: an unknown Claude tier doesn't suppress thresholds" || bad "threshold with unknown tier" "$out"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 95 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 92 1.5
out="$(us --watch)"; grep -q '^Threshold: claude work@x .* is at 92% of its 5h window, resets in 1.5h\. No other claude account has room on desktop\.$' <<<"$out" \
  && ok "threshold: 90% says when no other account has room" || bad "threshold no room" "$out"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
setwin claude personal@x 300 85
[ -z "$(us --watch)" ] && ok "threshold: an inactive account at 85% is quiet" || bad "threshold inactive"
mkusage "$U" 20 80 20 80; setwin codex work@x 10080 88 100
out="$(us --watch)"; grep -q '^Threshold: codex work@x (active on desktop) is at 88% of its week window' <<<"$out" \
  && ok "threshold: Codex accounts in use notify too" || bad "threshold codex" "$out"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 20 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 82 1.5; us --watch >/dev/null
[ -n "$(us --watch)" ] && ok "threshold: repeats without --ack (a failed send retries)" || bad "threshold lost unacked"
us --ack
python3 - "$U/a.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["ok"] = False; d["error"] = "down"; json.dump(d, open(sys.argv[1], "w"))
PY
[ -z "$(us --watch)" ] && ok "threshold: an outage doesn't notify" || bad "threshold outage"
mkusage "$U" 20 80 20 80; setwin claude work@x 300 82 1.5
[ -z "$(us --watch)" ] && ok "threshold: an outage doesn't clear the threshold state" || bad "threshold cleared by outage"
mkusage "$U" 20 80 20 80

# Pause at 95% (AGENTS.md → Pause at 95%): per machine, Pause when it starts, Resume when it ends
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 95 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 96 1.5
out="$(us --watch)"
[ "$(grep -c '^Pause: ' <<<"$out")" = 1 ] && grep -q '^Pause: claude on desktop: work@x is at 96% of its 5h window, resets in 1.5h, and no other Claude account has more than 10% left\. Tell every active lead on desktop to stop at a safe point' <<<"$out" \
  && ok "pause: 95% with no other account above 10% left prints one Pause line" || bad "pause start" "$out"
grep -q '^Pause in force: ' <<<"$(us)" && ok "pause: the plain report shows it" || bad "pause in report" "$(us)"
us --ack; [ -z "$(us --watch)" ] && ok "pause: not repeated after --ack" || bad "pause repeated"
setwin claude work@x 300 98 1.5; [ -z "$(us --watch)" ] && ok "pause: rising further stays quiet" || bad "pause re-alert"
setwin claude work@x 300 96 -0.1
out="$(us --watch)"
{ [ "$(grep -c '^Resume: ' <<<"$out")" = 1 ] && grep -q '^Resume: claude on desktop: the 95% pause is over (work@x is below 95% in every window)\. Tell the leads you paused on desktop to carry on\.$' <<<"$out"; } \
  && ok "pause: the reset prints one Resume line" || bad "pause resume on reset" "$out"
us --watch >/dev/null; [ -n "$(us --watch)" ] && ok "pause: Resume repeats until acked" || bad "pause resume lost unacked"
us --ack; [ -z "$(us --watch)" ] && ok "pause: Resume not repeated after --ack" || bad "pause resume repeated"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 30 80; us --watch >/dev/null; us --ack
setwin claude work@x 300 96 1.5
out="$(us --watch)"; ! grep -q '^Pause' <<<"$out" && grep -q 'Switch claude on desktop: work@x' <<<"$out" \
  && ok "pause: none when another account has room (switch instead)" || bad "pause with room" "$out"
rm -rf "$tmp/ustate"; mkusage "$U" 96 50 95 80; us --watch >/dev/null; us --ack
out="$(us)"; grep -q '^Pause in force: claude on desktop: work@x is at 96% of its week window' <<<"$out" \
  && ok "pause: the week window counts too" || bad "pause week" "$out"
mkusage "$U" 96 50 94 80 personal
out="$(us --watch)"; grep -q '^Resume: .*(desktop now uses personal@x)' <<<"$out" && ! grep -q '^Pause: ' <<<"$out" \
  && ok "pause: switching accounts ends it, and a new account under 95% doesn't pause" || bad "pause switch resume" "$out"
rm -rf "$tmp/ustate"; mkusage "$U" 20 80 95 80; setwin claude work@x 300 96 1.5; us --watch >/dev/null; us --ack
python3 - "$U/a.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["ok"] = False; d["error"] = "down"; json.dump(d, open(sys.argv[1], "w"))
PY
[ -z "$(us --watch)" ] && ok "pause: an outage doesn't resume" || bad "pause resumed by outage"
mkusage "$U" 20 80 95 80; setwin claude work@x 300 96 1.5
[ -z "$(us --watch)" ] && ok "pause: an outage doesn't clear the pause state" || bad "pause cleared by outage"
python3 - "$U/a.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1]))
for a in d["claude"]["accounts"]:
    if a["email"] == "work@x": a["windows"] = []; a["error"] = "token expired"
json.dump(d, open(sys.argv[1], "w"))
PY
out="$(us --watch)"; ! grep -q "^Resume" <<<"$out" && ok "pause: no reading for the account in use doesn't resume" || bad "pause resumed without a reading" "$out"
mkusage "$U" 20 80 20 80

echo "sitrep-ping"
printf '## Chiefofstaff run\n\n- Host: laptop\n- Run: `run_dddddddddddd`\n\n## Machines\n' > "$tmp/ledger3.md"
for job in sitrep watch retro; do
  CHIEFOFSTAFF_NO_PULL=1 CHIEFOFSTAFF_LEDGER="$tmp/ledger3.md" ORCA=/bin/false bin/sitrep-ping $job \
    && ok "$job: does nothing when chiefofstaff runs on the other machine" || bad "sitrep-ping $job acted for the other machine"
done
sp() { rm -f "$FAKE/sent"; CHIEFOFSTAFF_USAGE_FIXTURE="$U" CHIEFOFSTAFF_NOW_MS=$NOW CHIEFOFSTAFF_STATE_DIR="$tmp/state2" CHIEFOFSTAFF_NO_PULL=1 CHIEFOFSTAFF_LEDGER="$tmp/ledger4.md" ORCA="$tmp/fake-orca" bin/sitrep-ping "$@" >/dev/null; }
sp
{ grep -q 'run:run_dddddddddddd' "$FAKE/sent" && grep -q 'Scheduled sitrep' "$FAKE/sent" && grep -q 'Lead health, run run_dddddddddddd' "$FAKE/sent"; } 2>/dev/null \
  && grep -q 'Claude tier: normal' "$FAKE/sent" && ok "sitrep: mails chiefofstaff's run with the lead health and usage reports" || bad "sitrep-ping sitrep" "$(cat "$FAKE/sent" 2>/dev/null)"
sp watch; [ ! -e "$FAKE/sent" ] && ok "watch: silent when every lead is ok" || bad "watch mailed with nothing wrong" "$(cat "$FAKE/sent")"
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"identity_changed"}}}'
sp watch; grep -q 'Lead health alert' "$FAKE/sent" 2>/dev/null && grep -q 'remote-broken' "$FAKE/sent" \
  && ok "watch: alerts on a new problem" || bad "watch didn't alert" "$(cat "$FAKE/sent" 2>/dev/null)"
sp watch; [ ! -e "$FAKE/sent" ] && ok "watch: doesn't repeat an alert" || bad "watch repeated the alert"
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"live"}}}'
sp watch
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"identity_changed"}}}'
sp watch; grep -q 'Lead health alert' "$FAKE/sent" 2>/dev/null && ok "watch: alerts again after a problem clears and returns" || bad "watch didn't re-alert"
sp retro; grep -q 'Scheduled retrospective' "$FAKE/sent" 2>/dev/null && grep -q 'Open workspaces and lead chats' "$FAKE/sent" \
  && ok "retro: mails the retrospective prompt with the open-work list" || bad "sitrep-ping retro" "$(cat "$FAKE/sent" 2>/dev/null)"
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"live"}}}'
sp watch
fj worker-show-ctx_remote '{"ok":true,"result":{"server":{"name":"lap"},"observation":{"status":"identity_changed"}}}'
touch "$FAKE/fail-send"
sp watch 2>/dev/null; rm -f "$FAKE/fail-send"
sp watch; grep -q 'Lead health alert' "$FAKE/sent" 2>/dev/null && ok "watch: retries an alert whose send failed" || bad "watch lost an alert after a failed send"
cp "$FAKE/task-list.json" "$tmp/task-list.json"; rm -f "$FAKE/task-list.json"
sp watch 2>/dev/null; grep -q 'lead-health itself failed' "$FAKE/sent" 2>/dev/null && ok "watch: alerts once when the check itself fails" || bad "watch hid its own failure" "$(cat "$FAKE/sent" 2>/dev/null)"
sp watch 2>/dev/null; [ ! -e "$FAKE/sent" ] && ok "watch: doesn't repeat the failure alert" || bad "watch repeated its failure alert"
fj task-list '{"ok":true,"result":{"tasks":"not a list"}}'
sp watch 2>/dev/null; grep -q 'lead-health itself failed.*crashed' "$FAKE/sent" 2>/dev/null && ok "watch: alerts when the check crashes" || bad "watch hid a crash" "$(cat "$FAKE/sent" 2>/dev/null)"
cp "$tmp/task-list.json" "$FAKE/task-list.json"
sp bogus 2>/dev/null; [ $? = 2 ] && ok "rejects an unknown job" || bad "sitrep-ping accepted an unknown job"

# Threshold notices through sitrep-ping watch
cat > "$tmp/fake-notify" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s' "$1" >"$FAKE/notified"
[ ! -e "$FAKE/fail-notify" ]
NOTIFY
chmod +x "$tmp/fake-notify"
spn() { rm -f "$FAKE/notified"; CHIEFOFSTAFF_NOTIFY="$tmp/fake-notify" sp "$@"; }
rm -rf "$tmp/state2"; mkusage "$U" 20 80 20 80; spn watch; spn watch
setwin claude work@x 300 82 1.5
spn watch
grep -q '^chiefofstaff: usage: claude work@x (active on desktop) is at 82% of its 5h window, resets in 1.5h\.$' "$FAKE/notified" 2>/dev/null \
  && ok "watch: sends the Threshold lines to the notify command, prefixed" || bad "watch notify" "$(cat "$FAKE/notified" 2>/dev/null)"
grep -q 'Usage alert' "$FAKE/sent" && grep -q 'Threshold: claude work@x' "$FAKE/sent" && grep -q '80% or 90%' "$FAKE/sent" && grep -q 'also go to Sam through the notify command' "$FAKE/sent" \
  && ok "watch: the Usage alert mail carries the Threshold lines" || bad "watch mail thresholds" "$(cat "$FAKE/sent" 2>/dev/null)"
spn watch; { [ ! -e "$FAKE/sent" ] && [ ! -e "$FAKE/notified" ]; } && ok "watch: acked after both sends, nothing repeats" || bad "watch repeated thresholds"
rm -rf "$tmp/state2"; mkusage "$U" 20 80 20 80; spn watch
setwin claude work@x 300 91 1.5
touch "$FAKE/fail-notify"; spn watch 2>/dev/null; rm -f "$FAKE/fail-notify"
{ grep -q 'Usage alert' "$FAKE/sent" 2>/dev/null && grep -q 'Threshold: claude work@x' "$FAKE/sent"; } \
  && ok "watch: a failed notify send doesn't stop the mail" || bad "watch mail after notify failure" "$(cat "$FAKE/sent" 2>/dev/null)"
spn watch; { grep -q 'is at 91%' "$FAKE/notified" 2>/dev/null && grep -q 'Usage alert' "$FAKE/sent"; } \
  && ok "watch: a failed notify send leaves usage unacked, so the next run retries" || bad "watch ack after notify failure"
spn watch; [ ! -e "$FAKE/sent" ] && ok "watch: quiet once the retry succeeded" || bad "watch repeated after retry"
rm -rf "$tmp/state2"; mkusage "$U" 20 80 20 80; spn watch
setwin claude work@x 300 82 1.5
touch "$FAKE/fail-send"; spn watch 2>/dev/null; rm -f "$FAKE/fail-send"
[ ! -e "$FAKE/notified" ] && ok "watch: a failed mail sends no notice (the retry would duplicate it)" || bad "notice sent despite mail failure"
spn watch; { grep -q 'is at 82%' "$FAKE/notified" 2>/dev/null && grep -q 'Usage alert' "$FAKE/sent"; } \
  && ok "watch: after a failed mail the next run sends both" || bad "watch retry after mail failure"
cat > "$tmp/notify with space" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s|%s' "$#" "$1" >"$FAKE/notified"
NOTIFY
chmod +x "$tmp/notify with space"
rm -rf "$tmp/state2"; mkusage "$U" 20 80 20 80; spn watch; setwin claude work@x 300 82 1.5
rm -f "$FAKE/notified"; CHIEFOFSTAFF_NOTIFY="$tmp/notify with space" sp watch
grep -q '^1|chiefofstaff: usage: claude work@x' "$FAKE/notified" 2>/dev/null \
  && ok "watch: CHIEFOFSTAFF_NOTIFY is one executable path (spaces fine), message as its one argument" || bad "notify quoting" "$(cat "$FAKE/notified" 2>/dev/null)"
rm -rf "$tmp/state2"; mkusage "$U" 20 80 95 80; spn watch; setwin claude work@x 300 96 1.5
spn watch
grep -q 'Usage alert' "$FAKE/sent" && grep -q 'Pause: claude on desktop' "$FAKE/sent" && grep -q '95% pause started or ended' "$FAKE/sent" \
  && ok "watch: the Usage alert mail carries the Pause line" || bad "watch mail pause" "$(cat "$FAKE/sent" 2>/dev/null)"
grep -q 'Pause' "$FAKE/notified" 2>/dev/null && bad "watch: Pause lines must not go to the notify command" "$(cat "$FAKE/notified")" || ok "watch: Pause lines don't go to the notify command"
spn watch; [ ! -e "$FAKE/sent" ] && ok "watch: the Pause mail isn't repeated" || bad "watch repeated pause"
mkusage "$U" 20 80 20 80

echo "orca CLI"
out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin CHIEFOFSTAFF_CONFIG="$CHIEFOFSTAFF_CONFIG" CHIEFOFSTAFF_MACHINE=desktop bash -c '. bin/_common.sh; echo "$ORCA"' 2>&1)"
{ [ -n "$out" ] && [ "$out" != /usr/bin/orca ] && [ -x "$out" ]; } \
  && ok "timer environment finds Orca's CLI, not /usr/bin/orca ($out)" || bad "ORCA resolved to '$out' with a timer's PATH"

echo "start-chiefofstaff refusals"
wt="$tmp/wt"
if git worktree add -q --detach "$wt" HEAD 2>/dev/null; then
  cp templates/operator.md "$wt/operator.md"; cp templates/ledger.md "$wt/ledger.md"
  "$wt/bin/start-chiefofstaff" >/dev/null 2>"$tmp/err"; rc=$?
  { [ $rc = 3 ] && grep -q 'worktree' "$tmp/err"; } && ok "refuses in a worktree" || bad "worktree refusal" "rc=$rc $(cat "$tmp/err")"
  git worktree remove --force "$wt"
else skip "couldn't create a test worktree"; fi

tail -1 bin/start-chiefofstaff | grep -qx 'main "\$@"' && grep -qx 'main() {' bin/start-chiefofstaff \
  && ok "start-chiefofstaff runs inside main() (safe to pull over itself)" || bad "start-chiefofstaff must run everything inside main() and end with main \"\$@\""

echo "install-timers"
ti="$tmp/timers"
printf 'SITREP_TIMES="7:05 18:30"\nWATCH_MINUTES=10\nRETRO_DAY=Fri\nRETRO_TIME=09:00\nTIMER_LABEL=test.cos\n' >> "$tmp/test.conf"
bin/install-timers --out "$ti" >/dev/null && ok "writes units with --out" || bad "install-timers --out"
python3 - "$ti" "$here/bin/sitrep-ping" <<'PLIST' && ok "launchd plists parse, with the configured schedule" || bad "launchd plists"
import plistlib, sys
d, ping = sys.argv[1:]
p = {j: plistlib.load(open(f"{d}/test.cos-{j}.plist", "rb")) for j in ("sitrep", "watch", "retro")}
assert p["sitrep"]["ProgramArguments"] == ["/bin/bash", ping], p["sitrep"]
assert p["sitrep"]["StartCalendarInterval"] == [{"Hour": 7, "Minute": 5}, {"Hour": 18, "Minute": 30}]
assert p["watch"]["ProgramArguments"][2] == "watch" and p["watch"]["StartInterval"] == 600
assert p["retro"]["StartCalendarInterval"] == [{"Weekday": 5, "Hour": 9, "Minute": 0}]
assert p["retro"]["Label"] == "test.cos-retro"
PLIST
{ grep -qx 'OnCalendar=\*-\*-\* 07:05:00' "$ti/chiefofstaff-sitrep.timer" && grep -qx 'OnCalendar=\*-\*-\* 18:30:00' "$ti/chiefofstaff-sitrep.timer" \
  && grep -qx 'OnCalendar=\*-\*-\* \*:00/10:00' "$ti/chiefofstaff-watch.timer" && grep -qx 'OnCalendar=Fri \*-\*-\* 09:00:00' "$ti/chiefofstaff-retro.timer" \
  && grep -qx "ExecStart=$here/bin/sitrep-ping watch" "$ti/chiefofstaff-watch.service" && grep -qx "ExecStart=$here/bin/sitrep-ping" "$ti/chiefofstaff-sitrep.service"; } \
  && ok "systemd units carry the configured schedule" || bad "systemd units" "$(cat "$ti"/chiefofstaff-*)"
if command -v systemd-analyze >/dev/null; then
  systemd-analyze --user verify "$ti"/chiefofstaff-*.timer "$ti"/chiefofstaff-*.service >"$tmp/sa" 2>&1 \
    && ok "systemd units verify" || bad "systemd units verify" "$(cat "$tmp/sa")"
else skip "systemd-analyze not available"; fi
{ cat "$tmp/test.conf"; printf 'RETRO_DAY=Someday\n'; } > "$tmp/bad.conf"
CHIEFOFSTAFF_CONFIG="$tmp/bad.conf" bin/install-timers --out "$tmp/t2" >/dev/null 2>&1; [ $? = 2 ] && ok "rejects a bad schedule" || bad "install-timers bad schedule"

echo "files"
for f in .claude/skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' && sed -n '2,5p' "$f" | grep -q '^name:' && sed -n '2,6p' "$f" | grep -q '^description:' \
    && ok "skill frontmatter $f" || bad "skill frontmatter $f"
done
for f in $(grep -oE '`(bin|specs|templates|tests)/[A-Za-z0-9_./-]+`' AGENTS.md README.md .claude/skills/*/SKILL.md | sed -E 's/.*`(.*)`/\1/' | sort -u); do
  case "$f" in *'<'*|*'{'*|*'*'*) continue ;; esac
  [ -e "$f" ] && ok "referenced path exists: $f" || bad "docs reference a missing path: $f"
done

echo "live (read-only)"
if [ -n "${CHIEFOFSTAFF_TESTS_OFFLINE:-}" ] || [ ! -f "$real_conf" ] || ! { command -v orca >/dev/null && orca status >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }; then
  skip "orca/gh unavailable, no chiefofstaff.conf, or CHIEFOFSTAFF_TESTS_OFFLINE set"
else
  export CHIEFOFSTAFF_CONFIG="$real_conf"; unset CHIEFOFSTAFF_MACHINE
  owner="$(bash -c '. bin/_common.sh; echo "$GITHUB_OWNER"')"
  # The repo's own GitHub name; --dry-run so a wrong name can never create anything.
  self="$(basename "$(git remote get-url origin 2>/dev/null)" .git)"
  if [ -n "$owner" ] && [ -n "$self" ]; then
    out="$(bin/ensure-project "$self" --dry-run 2>&1)"; echo "$out" | grep -q 'nothing to do' && ok "ensure-project: $self already set up" || bad "ensure-project $self" "$out"
  else skip "ensure-project live checks need GITHUB_OWNER and an origin remote"; fi
  if [ -n "$owner" ]; then
    out="$(bin/ensure-project chiefofstaff-test-zz-not-a-repo --dry-run 2>&1)"
    echo "$out" | grep -q "created GitHub repo $owner/chiefofstaff-test-zz-not-a-repo (private)" && echo "$out" | grep -q 'git init' \
      && ok "ensure-project: plans a brand-new project" || bad "ensure-project new (dry)" "$out"
    [ ! -e "$HOME/$(bash -c '. bin/_common.sh; echo "${PROJECTS_REL:-Code}"')/chiefofstaff-test-zz-not-a-repo" ] && ok "ensure-project --dry-run changed nothing" || bad "dry run created a folder"
    bin/ensure-project zz-not-a-repo --owner zz-some-other-owner-zz --dry-run >/dev/null 2>"$tmp/err"; rc=$?
    { [ $rc = 3 ] && grep -q "won't create" "$tmp/err"; } && ok "ensure-project: refuses to create outside GITHUB_OWNER" || bad "owner refusal" "rc=$rc $(cat "$tmp/err")"
  fi
  bin/orca-account >"$tmp/acc" 2>&1 && grep -q '^claude:' "$tmp/acc" && ok "orca-account lists accounts" || bad "orca-account" "$(cat "$tmp/acc")"
  CHIEFOFSTAFF_STATE_DIR="$tmp/live-state" bin/usage >"$tmp/usage-live" 2>&1 && grep -q "^Claude tier: " "$tmp/usage-live" \
    && ! grep -q "Not read: $(bash -c '. bin/_common.sh; echo $CHIEFOFSTAFF_HOST')" "$tmp/usage-live" \
    && ok "usage reads this machine's Orca" || bad "usage live" "$(cat "$tmp/usage-live")"
  CHIEFOFSTAFF_STATE_DIR="$tmp/live-state" bin/lead-health >"$tmp/lh" 2>&1; rc=$?
  { [ $rc -lt 2 ] && grep -q '^Lead health, run ' "$tmp/lh"; } && ok "lead-health reads the live run (exit $rc)" || bad "lead-health live" "rc=$rc $(head -5 "$tmp/lh")"
  n="$(bash -c '. bin/_common.sh; chiefofstaff_sessions')"; [ "$n" -ge 0 ] 2>/dev/null && ok "chiefofstaff_sessions counts ($n here)" || bad "chiefofstaff_sessions" "$n"
fi

echo
echo "$pass passed, $fail failed, $skip skipped"
[ $fail = 0 ]
