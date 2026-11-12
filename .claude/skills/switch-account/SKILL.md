---
name: switch-account
description: Check usage and switch which Claude or Codex account the operator's agents use on any of their machines, or route work to another agent family. Use whenever the operator says "switch to <account>", "use my other Claude", "which account am I on", "use Codex on <account>", asks how much usage is left, or hits a usage limit and wants to move accounts.
---

# Switch account

Orca owns the accounts. Switching changes a machine's active account; with Orca's "Always
restart" setting for account switches on, running Claude sessions restart on it, busy ones
once idle. Switch when the operator asks, or right away at 90% of a window on the account
in use (`bin/usage` advises it; AGENTS.md → Usage and models), within the rules in
`operator.md` → Machines and accounts. Confirm in one line and log it in `ledger.md`.

## Usage first

`bin/usage` reads every Claude and Codex account's 5-hour and weekly usage from Orca on
every machine in `chiefofstaff.conf` (`--json` for scripts). It prints pace against time
to reset, the Claude tier, and a ready-to-run `bin/orca-account` command when the active
account on a machine is at 90% or more and another account has room. A reading marked
`(stale)` is over six hours old: Orca refreshes an inactive account when it next runs.

## The command

`bin/orca-account` (in this repo) talks to the local Orca app, the same call as its
account switcher:

```
bin/orca-account                         # list Claude + Codex accounts and their ids; * = active
bin/orca-account claude <email|id>       # this machine's Claude account (running sessions restart on it)
bin/orca-account codex <email|id>        # new Codex sessions use it
```

For another machine, point it at that machine's paired Orca app with its environment name
(`chiefofstaff.conf` → MACHINES):

```
ORCA_ENVIRONMENT=<env> bin/orca-account                 # list
ORCA_ENVIRONMENT=<env> bin/orca-account claude <id>     # switch
```

Match on email; when two entries share an email, use the id from the listing. Account ids
differ between machines, so list on the machine you're switching. Running Codex sessions
keep their account until they end.

Leads on another machine run inside that machine's Orca app (`--on <env>`), so they use
whichever account that app has selected.

## Other agent families

An agent family that isn't Claude or Codex (OpenCode with a provider of the operator's
choice, say) isn't an account: start a lead or worker with `--agent <name>` and Orca uses
that agent's own configured model. Moving Claude work to another family is the operator's
call (AGENTS.md → Usage and models).

## After switching

- Say which account is now active for which kind and machine, in one line.
- Add a line to `ledger.md` under Standing guidance, e.g. "Claude on <machine>:
  <account> since <date>", replacing any earlier line for that kind and machine.
- If the switch was because of a usage limit, mention which account hit it.
