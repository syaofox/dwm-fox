#!/usr/bin/env python3
"""Simple system package scanner - lists all installed packages."""

import shutil
import subprocess
import sys


def run(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError, PermissionError):
        return None


def list_python_packages():
    output = run([sys.executable, "-m", "pip", "list", "--format=columns"])
    if output:
        print("\n=== Python Packages ===")
        print(output)


def dpkg_packages():
    # ${binary:Package} drops any ":arch" qualifier for foreign architectures.
    output = run(
        ["dpkg-query", "-W", "-f=${binary:Package}\t${Version}\n"]
    )
    return output


def list_system_packages():
    # The Debian archive is the supported platform. rpm is probed as a
    # read-only convenience for anyone inspecting an existing multi-boot host.
    managers = [
        ("dpkg", dpkg_packages),
        ("rpm", lambda: run(["rpm", "-qa", "--qf", "%{NAME}\t%{VERSION}\n"])),
        ("flatpak", lambda: run(["flatpak", "list", "--columns=application,version"])),
        ("snap", lambda: run(["snap", "list"])),
    ]

    found = False
    for name, probe in managers:
        if name == "dpkg" and shutil.which("dpkg-query") is None:
            continue
        if name != "dpkg" and shutil.which(name.split()[0]) is None:
            continue
        output = probe()
        if output:
            print(f"\n=== {name} Packages ===")
            print(output)
            found = True

    if not found:
        print("No supported package database found.")


if __name__ == "__main__":
    list_system_packages()
    list_python_packages()
