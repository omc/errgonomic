# Contributing

This document captures how we develop `errgonomic`: the workflow, the quality gate, and the values that decide a judgment call when the rules run out.

## Environment

The toolchain is pinned by `flake.nix` and loaded automatically by `direnv`. A checkout with `direnv allow` already has the correct Ruby toolchain (ruby and the locked gem environment) on the path. The project is self-contained and targets multiple systems (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin): do not install tools globally or reach outside the repository, except where a task explicitly calls for it (for example, reading a script in a sibling project as a reference).

Gems are provided by [gems4nix](https://github.com/omc/gems4nix), which reads `Gemfile.lock` directly — there is no `gemset.nix`. When gem dependencies change, run `bundle lock --add-checksums` (preserving the platform list — gems4nix needs the `CHECKSUMS` section and the precompiled platform variants), then `rake gems4nix:groups` to regenerate the committed `gem-groups.json` group mapping.

Nontrivial development, debugging, and testing commands live as Rake tasks in the `Rakefile` rather than being re-typed ad hoc — they should be reproducible and not churn permission prompts. `rake -T` lists what is available.

## Development loop

We work test-first, in three beats:

1. **Red** — write a failing test that names the behavior you intend. Run it and watch it fail for the reason you expect. A test that passes the moment you write it was not testing the new behavior.
2. **Green** — write the least code that makes the test pass. Resist designing ahead of the test in front of you.
3. **Refactor** — with the test green, improve the shape of the code. The test is your safety net; the behavior must not change.

Each beat ends with a compiling, formatted tree. One small conceptual change per edit; multi-concern edits get broken up. Small, reversible steps beat large speculative ones.

## The gate — a ladder

The inner rungs run constantly; the outer rungs are slower and run when preparing to push or open a PR. Run them in order; do not skip ahead.

**Per edit, and before each commit (inner gate):**

```sh
bundle exec rubocop        # formatted & lint-clean
bundle exec yard doctest   # doctests pass — most behavior is specified here
bundle exec rake test      # unit tests pass (incl. the Rails integration test)
```

A change that fails any of these is not ready. Keep formatting-only changes in their own commit so they do not obscure a behavioral diff. `bundle exec rake` runs the full suite (test + yard:doctest) in one shot.

**Before push / PR (outer gate):**

```sh
bundle exec rake                 # full suite: unit tests + doctests
nix build .#errgonomic           # the gem builds as a derivation; rake runs in its checkPhase
nix flake check --all-systems    # builds every check on the local system, evaluates all four
```

**After push (CI gate):** a push is done when CI is green, not when `git push` succeeds. Check whatever CI this repo runs (`gh run list`, `gh run view --log-failed`); checks take minutes, so it is fine to schedule the check as a followup and keep working — but the change is not landed until they pass. A CI failure is a regression: diagnose it from the logs, reproduce it locally where you can, and capture it as a test so it cannot recur silently. CI earns you the coverage you cannot run locally — a target your machine isn't, a matrix leg, a slower suite — for free. Here, CI (`.github/workflows/main.yml`) runs `yard doctest` and `rake test` on the latest Ruby 3.4.x on ubuntu-latest, matching the Ruby pinned by the flake.

Tests *are* the requirements: a behavior is defined by the test that asserts it. Prefer doctests where an example clarifies a function's contract — they document and test at once and cannot drift out of date without failing the build. In this repo, the YARD `@example` blocks under `lib/**/*.rb` are the primary suite.

## Commits

- One logical change per commit. The subject names the conceptual change (not the file change); the body says why, when the why is not obvious.
- **Agents do not sign commits** unless explicitly directed. Pass `--no-gpg-sign` per commit (do not set `git config commit.gpgsign false`). Signing happens later, by a human, at review.
- Agents do not add co-author or generated-by trailers.

## Comments and documentation

Comments explain intent and rationale — the *why* behind a non-obvious choice. They must stand on their own: a reader should understand a comment without chasing a ticket, an external document, a previous version of the code, a project plan, or (rarely, and only when it genuinely aids understanding) another file. Write for the developer who arrives a year from now with none of today's context.

## What we value, in order

When two designs compete, prefer them in this order.

1. **Correct.** The code states its behavior and is tested against that statement. Invalid states are made unrepresentable rather than guarded against after the fact. Runtime failures produce diagnostics that tell an operator what went wrong and what to do.
2. **Simple.** The code reads clearly at the right level of abstraction, and is idiomatic and approachable to another developer. Fewer moving parts, fewer sources of truth.
3. **Performant.** Done well, the first two rarely cost us speed. Do not trade clarity for micro-optimization without a measurement that demands it.

We also keep abstraction just-in-time: let the compiler and tests tell us where a seam is needed rather than pre-abstracting, and refactor when a real need surfaces.
