#!/usr/bin/env python3
"""
resolve-file-bridge client: run Lua inside DaVinci Resolve from outside it.

    from bridge import Bridge
    b = Bridge(r"C:\\resolve-file-bridge")          # or env RESOLVE_BRIDGE_ROOT
    r = b.run('result = { comp = comp:GetAttrs().COMPS_Name }')
    print(r["result"])

CLI:
    python bridge.py ping
    python bridge.py exec "result = bridge.dump()"
    python bridge.py run examples/02_list_nodes.lua
    python bridge.py stop            # ask the listener to exit (no file left behind)
    (all take --root PATH, default $RESOLVE_BRIDGE_ROOT)

Protocol (see README): numbered inbox/cmd_NNNNNN.lua -> outbox/cmd_NNNNNN.comp whose CustomData
holds a hex-encoded JSON result. state.lua tells the listener where to resume. One client at a time.
"""
import argparse, binascii, json, os, re, sys, time

_NUM = re.compile(r"^cmd_(\d+)\.(lua|comp)(\.cancelled)?$")
_PAYLOAD = re.compile(r'payload\s*=\s*"([0-9a-fA-F]*)"')


class BridgeError(RuntimeError):
    pass


class Bridge:
    def __init__(self, root=None, timeout=120.0, poll=0.2, archive=True):
        root = root or os.environ.get("RESOLVE_BRIDGE_ROOT")
        if not root:
            raise BridgeError("bridge root not set (pass root= or set RESOLVE_BRIDGE_ROOT)")
        self.root = os.path.abspath(root)
        self.inbox = os.path.join(self.root, "inbox")
        self.outbox = os.path.join(self.root, "outbox")
        self.archive_dir = os.path.join(self.root, "archive")
        self.renders = os.path.join(self.root, "renders")
        for d in (self.inbox, self.outbox, self.archive_dir, self.renders):
            os.makedirs(d, exist_ok=True)
        self.timeout, self.poll, self.archive = timeout, poll, archive

    # ---- bookkeeping ----
    def _ids(self, folder):
        out = set()
        for f in os.listdir(folder):
            m = _NUM.match(f)
            if m:
                out.add(int(m.group(1)))
        return out

    def _write_state(self, first_pending):
        tmp = os.path.join(self.root, "state.lua.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("return { first_pending = %d }\n" % first_pending)
        os.replace(tmp, os.path.join(self.root, "state.lua"))

    def _path(self, folder, n, ext):
        return os.path.join(folder, "cmd_%06d.%s" % (n, ext))

    def _tidy(self):
        """Archive finished pairs left over from an interrupted client; return next free id."""
        inbox, outbox = self._ids(self.inbox), self._ids(self.outbox)
        for n in sorted(inbox & outbox):
            self._archive(n)
        everything = self._ids(self.inbox) | self._ids(self.outbox) | self._ids(self.archive_dir)
        pending = sorted(self._ids(self.inbox) - self._ids(self.outbox))
        nxt = (max(everything) + 1) if everything else 1
        nxt = max(nxt, self._read_state())   # never reuse a number the listener may already have passed
        return nxt, pending

    def _read_state(self):
        try:
            with open(os.path.join(self.root, "state.lua"), encoding="utf-8") as f:
                m = re.search(r"first_pending\s*=\s*(\d+)", f.read())
            return int(m.group(1)) if m else 1
        except OSError:
            return 1

    def _archive(self, n):
        if not self.archive:
            return
        for folder, ext in ((self.inbox, "lua"), (self.outbox, "comp")):
            p = self._path(folder, n, ext)
            if os.path.exists(p):
                os.replace(p, self._path(self.archive_dir, n, ext))

    # ---- decoding ----
    @staticmethod
    def decode(comp_path):
        with open(comp_path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        m = _PAYLOAD.search(text)
        if not m:
            raise BridgeError("no payload in %s" % comp_path)
        return json.loads(binascii.unhexlify(m.group(1)).decode("utf-8", "replace"))

    # ---- public API ----
    def run(self, code, timeout=None):
        """Run Lua code inside Resolve; returns dict(status, error, printed, result, elapsed, id)."""
        timeout = self.timeout if timeout is None else timeout
        n, pending = self._tidy()
        if pending:
            raise BridgeError("commands %s are still pending - is another client running, or is the "
                              "listener stopped?" % pending)
        self._write_state(n)
        cmd = self._path(self.inbox, n, "lua")
        with open(cmd + ".tmp", "w", encoding="utf-8") as f:
            f.write(code)
        os.replace(cmd + ".tmp", cmd)          # atomic: listener never sees half a file
        res_path = self._path(self.outbox, n, "comp")
        t_end = time.time() + timeout
        while time.time() < t_end:
            if os.path.exists(res_path):
                try:
                    res = self.decode(res_path)
                except (BridgeError, ValueError, OSError):
                    time.sleep(self.poll)      # file may still be being written
                    continue
                self._archive(n)
                self._write_state(n + 1)
                return res
            time.sleep(self.poll)
        # cancel: make sure a late listener won't run it, and skip past it
        if os.path.exists(cmd):
            os.replace(cmd, self._path(self.archive_dir, n, "lua.cancelled"))
        self._write_state(n + 1)
        raise TimeoutError("no answer from Resolve within %ss - is the listener running? "
                           "(Workspace > Scripts > Resolve Bridge Listen)" % timeout)

    def run_file(self, path, timeout=None):
        with open(path, encoding="utf-8") as f:
            return self.run(f.read(), timeout)

    def ping(self, timeout=15):
        return self.run('result = { bridge = bridge.version, comp = comp and comp:GetAttrs().COMPS_Name, '
                        'page = bridge.resolve() and bridge.resolve():GetCurrentPage() }', timeout)

    def stop(self, timeout=15):
        """Ask the listener to exit after this command (leaves no stop file behind)."""
        return self.run("bridge.stop(); result = 'stopping'", timeout)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Run Lua inside DaVinci Resolve via resolve-file-bridge")
    ap.add_argument("--root", default=os.environ.get("RESOLVE_BRIDGE_ROOT"))
    ap.add_argument("--timeout", type=float, default=120)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ping")
    sub.add_parser("stop")
    e = sub.add_parser("exec"); e.add_argument("code")
    r = sub.add_parser("run"); r.add_argument("file")
    a = ap.parse_args(argv)
    b = Bridge(a.root, timeout=a.timeout)
    if a.cmd == "stop":
        try:
            print(b.stop()["result"])
        except TimeoutError:
            print("listener not answering - if it is stuck, create a file named 'stop' in", b.root,
                  "(delete it again before the next start)")
        return 0
    res = b.ping() if a.cmd == "ping" else b.run(a.code, a.timeout) if a.cmd == "exec" else b.run_file(a.file, a.timeout)
    print(json.dumps(res, indent=2, ensure_ascii=False))
    return 0 if res.get("status") == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
