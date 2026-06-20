# TODO

- [ ] **Timezone and locale handling.** Automatically propagate the host timezone, with `--no-tz` to disable it, and offer locale propagation with `--loc`. These are small but genuinely thoughtful touches for interactive GUI/dev containers: log timestamps and locale-dependent tools behave like the host. docker-booster does not do either today. Cheap to add if wanted, and worth noting as a gap.
- [ ] **Help and usage output.** Add a `--help`/usage output that summarizes command-line options, Dockerfile directives, and common examples.
