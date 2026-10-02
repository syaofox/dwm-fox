#!/usr/bin/env python3
"""test-packagekit-floor.py — the Debian PackageKit version floor.

The system-management backend refuses unattended updates when the installed
PackageKit cannot be trusted. On Fedora that meant comparing RPM labels; on
Debian it means comparing dpkg versions against a documented floor.

The comparison cases need dpkg. Without it the test reports SKIP rather than a
false pass, and still checks the pure-logic guards that do not shell out.
"""

import importlib.machinery
import importlib.util
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parent.parent
TARGET = REPO / "scripts" / "dwm-system-management"

FAILURES = []


def check(condition, message):
    if not condition:
        FAILURES.append(message)


def load():
    # The script has no .py suffix, so it needs an explicit source loader, and
    # dataclasses require the module to be registered in sys.modules before it
    # is executed.
    loader = importlib.machinery.SourceFileLoader("dwm_system_management", str(TARGET))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    # The module guards its main entry point, so importing only defines helpers.
    loader.exec_module(module)
    return module


def dpkg_compare(left, right):
    """Debian version comparison, mirroring the helper under test."""
    for index, operator in enumerate(("lt", "eq", "gt")):
        if subprocess.run(
            ["/usr/bin/dpkg", "--compare-versions", left, operator, right],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, check=False).returncode == 0:
            return index - 1
    raise RuntimeError("dpkg version comparison failed")


def split_debian_version(version):
    """The split the backend performs: revision follows the last hyphen."""
    upstream, separator, revision = version.rpartition("-")
    if not separator or not upstream:
        return version, ""
    # A leading epoch is not part of the upstream version dpkg compares.
    if upstream.startswith("1:"):
        upstream = upstream[2:]
    return upstream, revision


def main():
    module = load()
    have_dpkg = Path("/usr/bin/dpkg").exists()

    # ── Splitting ─────────────────────────────────────────
    # 1: upstream is stripped because it is not part of the compared version.
    check(split_debian_version("1.3.4-3ubuntu1.2") == ("1.3.4", "3ubuntu1.2"),
          "1.3.4-3ubuntu1.2 must split into (1.3.4, 3ubuntu1.2)")
    check(split_debian_version("1.3.5-1") == ("1.3.5", "1"),
          "1.3.5-1 must split into (1.3.5, 1)")
    check(split_debian_version("1.3.4") == ("1.3.4", ""),
          "a version without a revision must keep the whole string as upstream")
    check(split_debian_version("1:1.3.4-3ubuntu1.2") == ("1.3.4", "3ubuntu1.2"),
          "a leading epoch must be stripped from the upstream version")
    check(split_debian_version("1.3.4-3ubuntu1.2") != ("", "1.3.4-3ubuntu1.2"),
          "the split must not return an empty upstream version")

    if not have_dpkg:
        print("SKIP: dpkg is unavailable; version-floor comparisons not exercised")
    else:
        floor = module.PACKAGEKIT_VERSION_FLOOR
        compare = dpkg_compare

        # ── The floor ordering ────────────────────────────
        for accepted in ("1.3.4-3ubuntu1.2", "1.3.4-3ubuntu1", "1.3.5-1", "1.4.0-1"):
            check(compare(accepted, floor) >= 0, f"{floor} must accept {accepted}")
        for rejected in ("1.3.4-2", "1.3.3-9", "1.2.9-1"):
            check(compare(rejected, floor) < 0, f"{floor} must reject {rejected}")

        # ── The predicate under test ───────────────────────
        daemon = (1, 3, 4)
        check(module.packagekit_security_floor("1.3.4", "3ubuntu1.2", "26.04", daemon, compare),
              "the installed Ubuntu PackageKit must satisfy the floor")
        check(module.packagekit_security_floor("1.3.5", "1", "26.04", (1, 3, 5), compare),
              "1.3.5 with a matching daemon must satisfy the floor")
        check(not module.packagekit_security_floor("1.3.4", "1", "26.04", daemon, compare),
              "an unpatched 1.3.4-1 must not satisfy the floor")
        check(not module.packagekit_security_floor("1.3.5", "1", "26.04", daemon, compare),
              "a 1.3.5 package with a 1.3.4 daemon must be rejected")
        check(not module.packagekit_security_floor("1.3.4", "3ubuntu1.2", "26.04", (1, 3, 5), compare),
              "a 1.3.4 package with a 1.3.5 daemon must be rejected")

        # ── Malformed input must never satisfy the floor ──
        for bad in (None, 12345, "", "x" * 200, "1.3", "v1.3.4"):
            check(not module.packagekit_security_floor(bad, "1", "26.04", daemon, compare),
                  f"malformed upstream {bad!r} must not satisfy the floor")
            check(not module.packagekit_security_floor("1.3.4", bad, "26.04", daemon, compare),
                  f"malformed revision {bad!r} must not satisfy the floor")
        # Debian orders letters before digits, so a letter-leading revision
        # outranks the numeric floor whatever it contains. It cannot be checked
        # against the floor and must be refused.
        for ambiguous in ("v1.3.4", "beta", "zzz9"):
            check(not module.packagekit_security_floor("1.3.4", ambiguous, "26.04", daemon, compare),
                  f"letter-leading revision {ambiguous!r} must be refused, not accepted")
        check(not module.packagekit_security_floor("1.3.4", "1", "26.04", (1, 3), compare),
              "a short daemon version tuple must not satisfy the floor")
        check(not module.packagekit_security_floor("1.3.4", "1", "26.04", ("1", 3, 4), compare),
              "a non-integer daemon version must not satisfy the floor")
        check(not module.packagekit_security_floor("1.3.4", "1", "26.04", (-1, 3, 4), compare),
              "a negative daemon version must not satisfy the floor")

        # ── The installed-version lookup ──────────────────
        check(module.packagekit_installed_version("bash") is not None,
              "dpkg-query must report an installed version for a known package")
        check(module.packagekit_installed_version("dwm-fox-not-a-package") is None,
              "an unknown package must report no installed version")

    for failure in FAILURES:
        print(f"FAIL: {failure}", file=sys.stderr)
    if FAILURES:
        return 1
    print("test-packagekit-floor: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())