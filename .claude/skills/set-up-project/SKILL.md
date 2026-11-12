---
name: set-up-project
description: Get a project ready to work on in Orca on any of the operator's machines, creating whatever is missing: the folder, the git repo, the GitHub repo (under GITHUB_OWNER, private by default) and the Orca project. Use before starting a lead on a repo Orca doesn't have on that machine, and whenever the operator wants something new built ("start a new project", "make a repo for…", "spin up a new app", "work on <repo> on the other machine").
---

# Set up a project

Every piece of new work lives in a git repo that is on GitHub and open as a project in
Orca on the machine that will do the work. `bin/ensure-project` gets it there, doing only
the steps that are missing.

```
bin/ensure-project <name>                    # this machine
bin/ensure-project <name> --on <machine>     # another machine from MACHINES (runs there over ssh)
bin/ensure-project <name> --dry-run          # show the plan, change nothing
  [--path <dir>] [--owner <github owner>] [--public]
```

What it does, in order, skipping anything already done:

1. **Find or make the folder.** It reuses a clone Orca already knows for that project, else
   one anywhere under `~/$PROJECTS_REL` (up to three levels deep) whose origin is the repo.
   Otherwise it clones from GitHub if the repo exists there, or creates
   `~/$PROJECTS_REL/<name>` (or `--path`).
2. **Git.** `git init -b main`, and a first commit (a one-line README if the folder is empty).
3. **GitHub.** Uses the existing repo and sets `origin` to its SSH URL, or creates
   `<GITHUB_OWNER>/<name>` (private unless `--public`) and pushes. It refuses to create
   repos for any other owner, and refuses if `origin` points somewhere else.
4. **Orca.** Imports the folder into its Orca project (`orca project setup-existing-folder`),
   which creates the project if needed and shows it in the sidebar. It upgrades a legacy
   `orca repo add` link the same way.

It ends by printing the Orca repo id for `worker-start --repo id:<id>`. For `--on`, start
the lead with `--on <that machine's Orca environment>`.

## Choosing the inputs

- **Name**: short, lowercase, hyphenated; it becomes the GitHub repo and folder name.
  Confirm a brand-new name with the operator only if they didn't give one or it's
  ambiguous.
- **Machine**: wherever the work will run (`operator.md` → Machines and accounts). Default
  to the machine chiefofstaff is on, unless the work needs another one.
- **Where on disk**: default `~/$PROJECTS_REL/<name>`. If the operator keeps similar repos
  in a subfolder, pass `--path`.
- **Visibility**: private unless the operator says public.
- **Repos owned by others** (an employer's or a shared org): it can clone and import
  existing ones, never create them. Pushes and PRs there follow `operator.md`.

## After

- Put the repo's path and Orca repo id in the lead spec and the ledger entry.
- A brand-new repo has no `AGENTS.md`. Have the lead write one as it learns the project.
- Never `orca repo add` a git repo: it makes a legacy link Orca's sidebar shows outside
  the project. (A folder with no git remote is the exception: `orca repo add --path
  <dir> --kind folder`.)
