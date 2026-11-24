# chiefofstaff

A chief of staff for a fleet of coding agents. You talk to one agent session; it starts,
supervises and relays for project leads that do the actual work, each in its own repo, on
whichever of your machines and accounts suits the work.

**This fully assumes you use [Orca](https://github.com/stablyai/orca).** Leads, messages,
runs, workspaces, account switching and machine pairing all go through Orca's
orchestration CLI, so without Orca nothing here works. The purpose is to coordinate agents
across accounts (several Claude or Codex subscriptions, used against their 5-hour and
weekly limits), agent families (Claude, Codex, OpenCode and whatever else Orca runs) and
multiple machines (paired Orca apps, with leads started on the machine where the work
belongs).

What it gives you:

- **One conversation.** You talk to chiefofstaff (typed, dictated, from Orca on your
  phone). It routes each request to a lead, carries your words to it, brings its
  questions back to you as short decision cards, and reports in a fixed four-part shape:
  Blocked on you, Broken, Working, Finished.
- **Leads that own their work.** Each lead runs in its repo under that repo's own
  instructions. Chiefofstaff passes intent, not instructions, and doesn't redo their work.
- **Durable memory.** A ledger in git holds current state, so a chat can restart, or move
  to another machine, and pick up where it was.
- **Watchdogs.** Lead health checks catch leads that stalled, are parked on a prompt, or
  never got their mail. Usage checks pace every account against its reset, advise or make
  account switches, and pause leads before an account runs dry.
- **A schedule.** Sitreps three times a day, a watch every 15 minutes, and a weekly
  retrospective in which chiefofstaff reviews its own work and proposes improvements.
- **An onboarding interview.** On first run, chiefofstaff asks how you work and writes
  your configuration.

## Requirements

- [Orca](https://github.com/stablyai/orca) on every machine, with its CLI (`orca`) working.
  For more than one machine, pair their Orca apps with each other (`orca environment
  add`), so each can start and reach agents on the others.
- Orca Settings → Orchestration → Nested worker depth of at least 2 (chiefofstaff → lead
  → the lead's own workers).
- An agent for chiefofstaff itself: Claude Code (it reads `CLAUDE.md`, which points at
  `AGENTS.md`) or any agent that reads `AGENTS.md`. `bin/last-chat` (where the previous
  chat left off) reads Claude Code's transcripts only; with another agent, start-up shows
  nothing there. Leads can be any agent family Orca runs.
- `bash`, `python3`, `git`, and the GitHub CLI `gh` (for creating project repos).
- Orca installed at `/opt/Orca` (Linux) or `/Applications/Orca.app` (macOS); set
  `ORCA_APP` to its folder otherwise. `bin/usage` and `bin/orca-account` use the app's own
  runtime to read and switch accounts (`bin/usage` falls back to `node` if it can't find
  it).
- Linux (systemd user timers) or macOS (launchd) for the schedule.

## Getting started

1. **Make your own private copy.** Your copy will hold your configuration, ledger and
   specs, which describe you, your machines and your work, so keep it private:

   ```
   gh repo create chiefofstaff --private --clone   # or create it in the GitHub UI
   cd chiefofstaff
   git remote add upstream https://github.com/nbramia/chiefofstaff-shared.git
   git pull upstream main
   git push -u origin main
   ```

   Clone it to the same path relative to your home on every machine (the default is
   `~/Code/chiefofstaff`).
2. **Open it in Orca** on the machine you want chiefofstaff to run on, start a chat in its
   main workspace, and say "start".
3. **Answer the onboarding interview.** Chiefofstaff finds that it isn't configured and
   interviews you: your machines and how they're paired, your accounts and which machine
   uses which, how you want updates, what it may approve on its own, what it must never
   do, and how you want leads to work. It writes `chiefofstaff.conf`, `operator.md` and
   `ledger.md`, installs the timers, runs the tests and gives its first update. Commit and
   push those files (chiefofstaff does it for you).
4. **Talk to it.** Ask for work in plain words. Say "update my setup" any time to rerun
   part of the interview.

## Your own instance

Files you own, written for you and kept in your private copy:

| File | What it holds |
|---|---|
| `chiefofstaff.conf` | Your machines, paths, GitHub owner, notify command and schedule (from `chiefofstaff.conf.example`) |
| `operator.md` | How you work: machines and accounts, updates, approvals, what never to do, how leads work (from `templates/operator.md`) |
| `ledger.md` | Chiefofstaff's current state: standing guidance, its Orca run, the open cards put to you and not yet answered, projects, open decisions (from `templates/ledger.md`). Entries point to PRs, issues and notes rather than restating them; `bin/ledger-edit` edits it and fails loudly when its target isn't there (`--set` rewrites one whole entry by name) |
| `specs/<project>.md` | One spec per lead, written from `specs/_lead-template.md` |
| `retros/` | Chiefofstaff's weekly retrospectives |

`.gitignore` lists these files, so they never land in a public checkout or an upstream pull
request by accident. Your private copy tracks them all the same: chiefofstaff adds new ones
with `git add -f`, and git keeps tracking a file once it is added.

Everything else (`AGENTS.md`, `bin/`, `tests/`, the skills, the templates) comes from
upstream. Get updates with `git pull upstream main`. Keep your own changes to how you work
in `operator.md`, not in `AGENTS.md`, and upstream merges stay clean. A change that would
help everyone belongs upstream as a pull request (without your own files).

## How the pieces fit

```
you ──(Orca desktop / Orca mobile)──▶ chiefofstaff chat  (Orca, ~/<CHIEFOFSTAFF_REL> on one machine)
                                         │  Orca orchestration run (ledger → Chiefofstaff run)
                  ┌──────────────────────┼──────────────────────────┐
                  ▼                      ▼                          ▼
   lead (this machine's repo)   lead on another machine (--on <env>)   admin lead (folder)
                  │                      │
                  ▼                      ▼
       the lead's own Orca workers (nested depth 2)
```

- **Chiefofstaff** is an Orca chat in this repo's main workspace, on one of your machines
  at a time (Where chiefofstaff runs). `AGENTS.md` makes every session there
  chiefofstaff.
- **Leads** are Orca supervised workers (`orca orchestration worker-start --keep-open`),
  one per project or admin thread, each in its own worktree. Every lead is a normal Orca
  session you can open and talk to.
- **Messages** go through Orca's orchestration mailbox: leads report with `worker_done`,
  `decision_gate`, `question` or `escalation`, and Orca wakes chiefofstaff. Chiefofstaff
  talks to a lead with `orca orchestration send --to dispatch:<id>`.
- **Specs.** Each lead starts from a spec written from `specs/_lead-template.md`: your
  request in your words, plus standing sections on how to work, what to ask about, and
  how to report, filled from `operator.md`.

## Who decides what

Chiefofstaff is your single interface and a relay, not a second planner:

- **Leads own their work.** A lead decides the plan, approach, verification and landing,
  following its repo's `AGENTS.md` and your global instructions.
- **Chiefofstaff carries intent.** It adds no requirements, criteria or limits of its own.
- **Chiefofstaff decides only** logistics (repo, machine, project setup, starting and
  closing leads, account switches within your rules), answers you already gave, and
  approvals you would clearly give. Everything else comes to you as a decision card
  carrying the lead's recommendation.
- **Approvals.** When a lead is parked on a permission prompt, chiefofstaff finds it
  (`worker-show` → `observation.agentWait`) and answers it if the action follows from the
  task, has a sound reason, stays in that repo or machine, and isn't destructive, costly or
  visible to others. It logs each approval in the ledger.
- **Questions.** Leads ask with `orca orchestration ask`. Chiefofstaff shows you numbered
  cards; you answer however you like ("1 B, 2 A", or in words), and it replies on the
  same message, which wakes the lead.
- **Always your call:** irreversible or destructive actions, spending money, anything
  another person will see, changing what a project is for, and anything `operator.md`
  adds.

## Machines

`chiefofstaff.conf` → `MACHINES` lists every machine, one line each:
`name|hostname|orca-environment|ssh-alias`.

- A script knows which machine it runs on by matching `hostname -s` against the hostname
  field; the others are the "other machines" it reaches through Orca with
  `--environment <orca-environment>` and over ssh with the alias.
- A lead on another machine runs inside that machine's Orca app (`worker-start --on
  <env>`): it shows in that machine's window and uses the account selected there. Use that
  machine's repo id (`orca repo list --environment <env>`).
- One machine works too: list only it.
- If an environment stops answering, that machine's Orca app is closed or the network
  path between the machines is down. Re-pair by creating a pairing code in the target
  machine's Orca, then `orca environment add --name <env> --pairing-code '<code>'` on the
  other.
- On Linux, `bin/_common.sh` finds Orca's CLI shim under `~/.config/orca/` before looking
  on `PATH`, because `/usr/bin/orca` on many desktops is the GNOME screen reader, which
  hangs when a timer runs it.

## Setting up a project

`bin/ensure-project <name> [--on <machine>] [--dry-run]` does whichever of these is
missing: find or create the folder (reusing an existing clone under `~/$PROJECTS_REL`,
else cloning from GitHub, else creating `~/$PROJECTS_REL/<name>`), git init and a first
commit, create `<GITHUB_OWNER>/<name>` on GitHub (private by default; never for other
owners) and push, and import the folder into its Orca project. It prints the Orca repo id
for `worker-start`. Details: `.claude/skills/set-up-project/`.

## Accounts and usage

Orca manages agent accounts per machine. `bin/orca-account` lists them and switches a
machine's active Claude or Codex account (the same call as Orca's account switcher);
`ORCA_ENVIRONMENT=<env>` points it at another machine's Orca. With Orca's "When you switch
accounts while Claude is running in terminals: Always restart" setting on, running Claude
sessions restart on the new account once idle. Rules for which machine uses which
account live in `operator.md`. Details: `.claude/skills/switch-account/`.

`bin/usage` reads `accounts.list` from Orca on every machine (each account's 5-hour and
weekly usage, reset times and paid extra-usage spend, for active and inactive accounts).
The same account on several machines merges by email, newest reading first. For each
window it reports pace: budget left against time left. Across the Claude accounts' weekly
windows that ratio gives the tier (normal ≥ 1, lean ≥ 0.6, conserve ≥ 0.3, critical below,
exhausted when every account is at a limit); `AGENTS.md` → Usage and models says what each
tier means. It advises a switch when a machine's active account is at 90% or more of a
window and another account is below 90% in all of its windows.

`bin/usage --watch` also reports:

- **Thresholds**: 80% and 90% crossings of every window of every Claude and Codex account
  in use, once per account, window and reset time, as `Threshold: …` lines. `sitrep-ping
  watch` sends those lines to `NOTIFY_CMD`, if set (`CHIEFOFSTAFF_NOTIFY` overrides it),
  and puts them in the Usage alert mail. It acks usage only when both sends succeeded.
- **Pause at 95%**: per machine, the Claude account active there is at 95% or more of a
  live window and no other Claude account is below 90% in all of its windows. It prints a
  `Pause: …` line when that starts and a `Resume: …` line when it ends. These go in the
  mail only.

Alert state lives in `~/.local/state/chiefofstaff/`.

## Scheduled wake-ups and lead health

`bin/install-timers` installs three jobs on a machine (systemd user timers on Linux,
launchd agents on macOS), from the schedule in `chiefofstaff.conf`. Install them on every
machine: each run pulls the repo, reads `ledger.md` → Chiefofstaff run, and mails that run
only if the ledger's Host is this machine, so exactly one chiefofstaff wakes.

| Job | When (default) | Mails chiefofstaff |
|---|---|---|
| `sitrep` | 08:30, 12:30, 17:30 | "Scheduled sitrep", with the ledger's open cards and `bin/lead-health`'s and `bin/usage`'s reports |
| `watch` | every 15 min | "Follow-up due" for each `bin/follow-up` whose time has passed (once each, on the next run after the machine comes back if it was off); "Notices" with what your bots and jobs sent you (README → Notices); "Lead health alert" when `bin/lead-health --watch` finds a new problem; "Usage alert" when `bin/usage --watch` finds the tier worse, new switch advice, a threshold crossing, or a pause starting or ending |
| `retro` | Sundays 16:00 | "Scheduled retrospective", with `bin/open-work`'s list of open workspaces and lead chats for the weekly cleanup review |

`bin/lead-health` lists each active lead in chiefofstaff's run as `ok` or `STALLED`, with
its machine and last output time, and the lead reports chiefofstaff hasn't handled.
STALLED means Orca can't observe the lead's process, it's parked on a prompt
(`agentWait`), mail to it has sat unread for 15 minutes while the lead showed no output
either, or it's on another machine whose inbox can't be read. Each lead's line shows its
last words, and an `ok` lead quiet for 10 minutes gets a verdict: `waiting` (on a worker,
build, review, you or chiefofstaff, or its own open question) or `idle` (ended its turn
and waits on nothing). Unread mail to a finished lead shows as `UNSENT` until it is resent
or dismissed (`--dismiss <msg or dispatch>`). A machine whose Orca doesn't answer (asleep
or off) is one `OFFLINE` note naming its leads, with no alert. A task Orca still lists as
open whose worker finished shows as done. An active lead Orca would close when it finishes
is kept open on the spot. The watch job counts a problem as alerted only after its mail
went out, so a failed send is retried.

`bin/follow-up "<when>" "<note>"` (`+30m`, `+2h`, `+1d`, `HH:MM`, `YYYY-MM-DD [HH:MM]`) is
how chiefofstaff sets itself a time to come back to something; `--list` and `--cancel <id>`
manage them. They live in `~/.local/state/chiefofstaff/follow-ups.json` on the machine that
set them, so one set before chiefofstaff moves machines stays behind: check `--list` there.
The watch drops each follow-up only after its mail went out, so a failed send retries.

### Relayed messages

Optional. `bin/relay-message [--via <source>] [--at <time>] [message]` mails chiefofstaff's
run a message from you that came through another tool: point a voice-capture app, a phone
shortcut or a mail rule at it (message on stdin or as arguments). It finds the run from the
ledger, goes through the paired Orca when chiefofstaff runs on another machine, and exits
non-zero when nothing was sent, so the calling tool can retry. Chiefofstaff echoes back
what it heard before acting (`AGENTS.md` → Relayed messages).

### Notices

Optional. Chiefofstaff can watch what your own bots, jobs and services send you on their
own (a chat bot's alerts, a nightly job's summary) and route a fix when one means something
is broken (`AGENTS.md` → Notices). A bot can't read back what it sent, so each sender also
appends a copy of each notice to a log, `NOTICE_LOG` on `NOTICE_LOG_MACHINE`
(`chiefofstaff.conf`), one JSON object per line:

```
{"ts": "2026-01-05T11:00:00Z", "bot": "alerts-bot", "source": "myapp/worker", "text": "Job failed: …"}
```

`ts` is UTC ISO 8601, `bot` names the bot or channel, `source` names the sender, `text` is
the message as sent. Senders append one whole line per message, under a lock (`flock`),
and never let a failed write stop the send. Leave out conversations: only notices a sender
sends on its own.

`bin/notices --watch`, run by the watch, prints the entries chiefofstaff hasn't seen (at
most 30 a run; the rest come next time), skipping chiefofstaff's own notices (text starting
`chiefofstaff:`), and `sitrep-ping watch` mails them as "Notices", marking them seen only
after the mail went out. On first use on a machine it starts at the log's end, so old
notices aren't replayed. From another machine it reads the log over ssh.
`bin/notices --tail <n>` shows recent ones, seen or not.

A job can also fail without sending anything (killed, crashed, never started). For a job
that should report every day, add `"label|source|text|from|by"` to `EXPECTED_NOTICES`: from
`by` (local time), a day with no entry from `source` containing `text` since `from` adds one
"chiefofstaff check: no '<label>' notice" block to the mail, once a day. A log with nothing
from before `from` is too new to judge, so it stays quiet.

### Vault links

Optional, for an Obsidian vault. Orca's chat opens only `http:`, `https:` and `mailto:`
links, so an `obsidian://` link there isn't clickable. A note link is an ordinary web link
instead: `bin/vault-link "<path inside the vault>"` prints
`[<note name>](http://<VAULT_LINK_HOST>:<port>/o/<encoded path>)`, and
`bin/vault-link-server` answers it with a small page that sends the browser on to
`obsidian://open?vault=<VAULT_NAME>&file=<path>`, with an "Open in Obsidian" button, so the
note opens on whichever device was clicked. On a phone it leaves the vault out unless the
link names one, and Obsidian uses the vault it has open. The server answers nothing else
(every other path is a 404) and listens only on `VAULT_LINK_ADDRS`: loopback plus an
address your devices reach privately, such as a tailnet address, never a public one.

Run the server as a service on one machine that your devices can reach, and set
`VAULT_LINK_HOST` to the name they reach it by. Prefer a name to an IPv4 address: some
IPv6-only networks rewrite IPv4 literals through NAT64, which bypasses a private network.
A systemd user unit for it:

```
[Service]
ExecStart=%h/Code/chiefofstaff/bin/vault-link-server
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

`Restart=always` covers a private-network address that isn't up yet at boot. A browser may
ask before handing a link to another app, and the tab it opened stays open.

After changing the schedule, rerun `bin/install-timers`. `bin/install-timers --remove`
takes the jobs off a machine.

## Where chiefofstaff runs, and starting it

Chiefofstaff runs on one machine at a time. `ledger.md` → Chiefofstaff run records which
machine (Host) and its Orca run (Run); the run lives in that machine's Orca.

To start or restart: open a chat in this repo's main workspace on the machine you want and
say anything. The agent runs `bin/start-chiefofstaff` first, which:

1. Stops with NOT CONFIGURED if `chiefofstaff.conf`, `operator.md` or `ledger.md` is
   missing, or this machine isn't in `MACHINES` (the agent then runs the onboarding
   interview).
2. Refuses unless it's in the main checkout `~/$CHIEFOFSTAFF_REL` (a worktree would have
   its own copy of the ledger).
3. Pulls the repo. If that changed anything, it restarts on the new version and says
   which instruction files changed, so the session re-reads them.
4. Refuses if another session is open in this machine's chiefofstaff workspace, or any
   session is open in another machine's, or the ledger names a machine whose Orca can't
   be reached to check.
5. Same machine as the ledger: takes over the recorded run, or creates a new one if it's
   gone. Another machine: moves chiefofstaff here with a new run, records it in the
   ledger, and lists leads still attached to the old run.
6. Prints where the previous chat left off (`bin/last-chat`), unhandled mail, open
   tasks, the lead health report, and ledger entries that need trimming.

## Cleanup

Each lead leaves a git worktree and branch, an Orca workspace and dispatch with a
terminal, a spec in `specs/`, and a ledger entry. Leads are kept open (`--keep-open`, and
`bin/keep-open <dispatch>` confirms it from Orca's records on every machine), so nothing
closes on its own. Cleanup happens in a weekly review with you: the retrospective mail
carries `bin/open-work`, every workspace on every machine that isn't a main checkout, with
its branch, PR, last activity, chats and chiefofstaff leads, marked `close?` when nothing
is working there and the PR is merged or closed or it has been idle 7 days. Chiefofstaff
closes what you pick (`AGENTS.md` → Closing a project). The exception is an ask you call a
one-off: chiefofstaff closes that lead's chat and workspace itself once it has relayed the
result.

## Permissions

Leads are most useful when their agents skip permission prompts (Orca Settings → Agents
sets each agent's launch flags), because nobody watches their terminals. That is your
choice to make. Either way, chiefofstaff's safety comes from `AGENTS.md` and
`operator.md`: no project work itself, and escalation for anything destructive, costly,
external or ambiguous. `bin/lead-health` finds leads parked on prompts.

## Tests

`tests/run.sh` checks the scripts offline against a fake `orca` and a test configuration
with two machines: syntax, configuration loading, the ledger helpers and
`bin/ledger-edit`, `bin/lead-health`'s verdicts, offline notes, dismissals and alert
de-duplication, `bin/lead-continue` and its check that a follow-up started, `bin/lead-move`,
`bin/keep-open`, `bin/open-work` (including listings too large for an argument),
`bin/follow-up` and the watch mailing each due one once, the sitrep mail's open cards,
`bin/relay-message`, `bin/notices` and the watch mailing each notice once (and expected
notices that didn't come), `bin/vault-link` and `bin/vault-link-server`, `bin/last-chat`, `ensure-project` reporting an Orca refusal, `bin/usage`'s pace, tiers, switch advice, thresholds and pauses
(on fixture snapshots), `sitrep-ping`'s three jobs acting only on chiefofstaff's machine,
`bin/install-timers`' units, `start-chiefofstaff` refusing in a worktree, skill
frontmatter, and that every path the docs mention exists. When `orca` and `gh` work and
`chiefofstaff.conf` exists, it also runs read-only live checks; `CHIEFOFSTAFF_TESTS_OFFLINE=1`
skips those. Run it after changing `bin/`. Not covered: takeovers and moves between
machines, and real repo creation, because each changes live state.

## Known limits

- Orca's CLI can't type into chat-mode sessions, so a new chiefofstaff chat only starts
  once you send it a first message.
- Orca's run record doesn't say which session coordinates it, so `bin/start-chiefofstaff`
  counts open sessions in the chiefofstaff workspace instead.
- Orca's "Always restart" account-switch setting covers Claude sessions only; Codex
  running sessions keep their account.
- Remote (`--on <env>`) workers that stop without `worker_done` aren't reported
  automatically. `bin/lead-health` catches them.
- A finished lead takes no more mail: `send` to its dispatch fails with
  `dispatch_inactive`, and on another machine a `reply` to its `worker_done` is accepted
  but never delivered. `bin/lead-continue <dispatch> --spec-file <file>` starts a
  follow-up dispatch in the same chat, keeping its session and context; with `--terminal`
  and `--worktree` it adopts any existing chat as a lead. Orca can accept a start and fail
  it a moment later (a chat with a dispatch still open takes no second one), so it refuses
  a chat with an open dispatch in chiefofstaff's run, then reads the new dispatch back: its
  last line is `STARTED`, `NOT SENT` (exit 1) or `NOT CONFIRMED` (exit 3).
- Orca can't move a chat to another workspace, and an account switch can leave a lead's
  terminal with no agent. `bin/lead-move <dispatch> --repo <selector> (--spec-file <f> |
  --spec <text>)` starts a fresh kept-open lead in a new workspace of that repo, told to
  read the old one's transcript first.
- Messages to a lead on another machine can fail silently when the two Orca apps run
  different versions: `send` says `queuedFor=worker`, the mail sits unhandled in the
  other machine's inbox, and `worker-show` reports `observation.status:
  identity_changed`. Hence the receipt check in `AGENTS.md` → Leads; keep Orca at the same
  version everywhere.
- Some agents refuse certain bulk or destructive commands outright, with no prompt to
  approve. Chiefofstaff runs those another way (an allow rule for that exact command, or
  its own session) and says which.

## License

MIT; see `LICENSE`.
