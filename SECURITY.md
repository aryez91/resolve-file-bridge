# Security

resolve-file-bridge is remote code execution **by design**: any `.lua` file that appears as the next
numbered command in `inbox/` runs inside DaVinci Resolve with the same rights as Resolve itself - it can
change or delete project content, start renders, and use the `bmd`/`os` functions Resolve exposes.

Recommendations:
- Keep the bridge folder on a local disk, writable only by you. Do not put it in a synced/shared folder
  (Dropbox, network share) that other people or programs can write to.
- Run the listener only while you need it; stop it with the `stop` file.
- When an AI agent drives it, review what it changes. The bundled skill tells agents to build beside
  your work and ask before changing your output, but you remain in control.
- Results are written to `outbox/` and `archive/`; they can contain project, node and file names.

Report vulnerabilities via a GitHub issue marked [security] (no exploit details) or the maintainer's email.
