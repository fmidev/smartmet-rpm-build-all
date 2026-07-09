# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`smartmet-rpm-build-all` orchestrates a full, topologically-ordered CI build of every SmartMet RPM package across the ~65 member repos. The output is a tested local yum repository (a `dist.tar` artifact) containing every successfully-built RPM. It runs nightly on CircleCI.

The orchestrator does **not** build anything itself. It generates a CircleCI workflow whose nodes are per-package build/test jobs that each clone the member repo and call `ci-build` (provided by `docker-smartmet-cibase`).

## Common commands

```bash
make                  # Regenerate .circleci/config.yml from .circleci/config.tmpl.yml + current spec files
make force            # Wipe the /tmp/specs/ spec cache and regenerate from scratch — use after any spec change in a member repo
make check            # Verify the committed config.yml matches what `make` would produce (used in CI)
```

There are no unit tests. Validation is "regenerate the config and run a full build."

## How a build is triggered

The CircleCI workflows are gated by the `perform_build` pipeline parameter. A run happens when:

1. The nightly **scheduled** workflow fires the `rebuild_config` job, which runs `make force`, commits the regenerated `config.yml`, and pushes it.
2. That push triggers the **on-commit** workflow with the freshly-regenerated dep graph, which then builds and tests every module.

So: the only way to start a full build is to commit-and-push a `config.yml` change. Pushing this repo with a touched `config.yml` is the manual override (`make force && git commit -am "..." && git push`).

## Architecture — the critical bits

### `ci-config-rebuild.pl` is the whole brain

This 480-line Perl script (run by the Makefile) is the orchestrator:

1. **Seed module set** — hardcoded `%::modules` hash near the top (~22 top-level plugins, tools, and the server). Transitively reachable libraries/engines are discovered automatically.
2. **Spec fetching** — for each module, downloads `https://raw.githubusercontent.com/fmidev/<module>/master/<spec>.spec` into `/tmp/specs/`. Cached; `make force` invalidates. The default branch is `master`; per-module branch overrides live in the `%::modules` hash.
3. **Spec parsing** — extracts lines matching `^Requires:`, `^BuildRequires:`, and `^#TestRequires:`. Strips the `-devel` suffix and the version constraint (everything after the first whitespace). Filters to packages starting with `smartmet-` and not on the `%ignore` list (`smartmet-test-data`, `smartmet-engine-grid-test`, `smartmet-SFCGAL-libs`, `smartmet-library-spine-plugin-test`, `smartmet-trajectory-formats`, `smartmet-trajectory`).
4. **Dep graph** — `%::builddeps` (from `BuildRequires:`) and `%::testdeps` (from `Requires:` + `#TestRequires:`). Recurses into every discovered dependency.
5. **Template expansion** — reads `.circleci/config.tmpl.yml`, finds `#template build`, `#template test`, `#template pre`, `#template post`, `#template deptree` blocks, and emits per-module job definitions plus the workflow's `requires:` tree:
   - `build-X` requires `test-Y` for every Y in `%::builddeps{X}`
   - `test-X` requires `build-X` plus `test-Y` / `build-Y` for each test dep
   - Tests are skipped (only build job emitted) for any module that has a `.circleci/disable-tests-in-ci` file in its repo — the script probes for this with a `curl` HEAD against the raw GitHub URL, cached in `%::test_required_cache`

### Two structural caveats that cause real failures

These are not theoretical — they bite regularly. Understand both before debugging a CI failure or proposing changes.

**1. The dep graph is frozen at config-generation time.** When a developer adds `BuildRequires: smartmet-library-foo-devel` to a member repo's spec, the build-all workflow does **not** know about it until someone (a) regenerates `config.yml` here and (b) commits + pushes. Until then, `build-X` will be scheduled in parallel with `build-foo`, the `dnf install` will run before `foo` lands in the local repo, and X will fail with `No matching package to install: smartmet-library-foo-devel`. The fix is always `make force && git commit -am "..." && git push` in this repo.

**2. Version constraints are discarded.** `ci-config-rebuild.pl` strips everything after the package name (line ~107: `$b =~ s/\s.*$//`). The dep graph has no notion of `>= 26.4.13`. So even with a correctly regenerated graph, if X requires `>= 27.0.0` of Y but Y on master is at 26.5.5, build-all will happily order them correctly — and X's actual `dnf install` will still fail at run time. There is no pre-flight version-compatibility check today.

### Per-job runtime model (`config.tmpl.yml`)

Each `build-X` job:
1. Disables `smartmet-open` and `smartmet-open-beta` yum repos (so dep resolution uses *only* the local repo built by this workflow).
2. Attaches the `/dist` workspace (RPMs from upstream jobs).
3. Symlinks `/dist/*.rpm` into `/repo`, runs `createrepo_c`, writes `/etc/yum.repos.d/localrepo.repo` pointing there with `priority=1`.
4. Runs `./getsource.sh` to clone the member repo (branch fallback: same name → `devel` → `master`; the script currently only attempts `$CIRCLE_BRANCH` directly — see comment on line ~37).
5. `cd /tmp/build && ci-build deps && ci-build rpm`. Persists the new RPMs back to `/dist` workspace.

Each `test-X` job: same setup, then `yum install` everything in `<module>.lst`, then `ci-build testprep && ci-build test`.

The `preprep` job runs `make check` to fail fast if someone forgot to commit a regenerated `config.yml`, then primes the workspace with non-CI-built RPMs (`smartmet-test-data`).

The `archive` post-job runs `createrepo_c /dist` and tars it as the workflow's artifact.

### `getsource.sh`

Runs inside the build container. Reads `$CIRCLE_JOB` (e.g. `build-smartmet-engine-contour`), strips the `build-`/`test-` prefix to derive the module name, clones `https://github.com/fmidev/<module>` into `/tmp/build`. Branch selection: if `$CIRCLE_BRANCH` is one of `RHEL7|RHEL8|RHEL9` it uses `master` for the smartmet repo; otherwise it uses `$CIRCLE_BRANCH` directly. The README's "fallback to devel then master" is **not** currently implemented — only the requested branch is tried.

## When you change something

- **Edited `config.tmpl.yml`**: run `make`, commit both files. CircleCI cannot regenerate config and restart on its own — it must already be present.
- **Added/removed a top-level module**: edit `%::modules` in `ci-config-rebuild.pl`, then `make force`.
- **Added a module to ignore**: edit `%ignore` in `ci-config-rebuild.pl`, then `make force`.
- **Spec change in a member repo (any of the ~65 others)**: nothing in this repo needs to change, but you must `make force && git commit && git push` here to make the next build see it.

The README warns about merge conflicts on `config.yml` — it's regenerated daily, so always resolve by overwriting with whatever `make` produces.
