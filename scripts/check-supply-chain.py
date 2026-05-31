#!/usr/bin/env python3
"""Local supply-chain and secret-safety gate for the Flutter MVP."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"

SKIP_DIR_NAMES = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    ".vscode",
    "build",
}

BINARY_SUFFIXES = {
    ".a",
    ".apk",
    ".class",
    ".dex",
    ".gif",
    ".ico",
    ".jar",
    ".jpeg",
    ".jpg",
    ".keystore",
    ".png",
    ".so",
    ".webp",
    ".zip",
}

SECRET_PATTERNS = {
    "OpenAI API key": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"),
    "OpenAI Realtime client secret": re.compile(r"\bek_[A-Za-z0-9_-]{20,}\b"),
    "OpenAI session token": re.compile(r"\bsess-[A-Za-z0-9_-]{20,}\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
}

# Least privilege for the phone-only MVP is exactly these two permissions:
# RECORD_AUDIO for live microphone capture and INTERNET for the direct
# phone-to-OpenAI network path (realtime translation, scoped AI chat, summary
# and export generation). Both are required; anything else needs review.
ALLOWED_ANDROID_PERMISSIONS = {
    "android.permission.RECORD_AUDIO",
    "android.permission.INTERNET",
}

# Product-critical permissions that must be declared in the source main
# manifest. A release build that drops INTERNET cannot reach OpenAI, so this
# gate catches that regression in CI before an APK is ever built (#41).
REQUIRED_ANDROID_PERMISSIONS = {
    "android.permission.RECORD_AUDIO",
    "android.permission.INTERNET",
}


@dataclass(frozen=True, order=True)
class PackageQuery:
    ecosystem: str
    name: str
    version: str
    source: str


class CheckFailure(Exception):
    pass


def run_command(args: list[str], cwd: Path) -> str:
    completed = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        print(completed.stdout)
        raise CheckFailure(f"Command failed: {' '.join(args)}")
    return completed.stdout


def load_pub_packages(root: Path) -> list[PackageQuery]:
    output = run_command(["dart", "pub", "deps", "--json"], root)
    deps = json.loads(output)
    packages: list[PackageQuery] = []
    for package in deps.get("packages", []):
        if package.get("source") != "hosted":
            continue
        packages.append(
            PackageQuery(
                ecosystem="Pub",
                name=package["name"],
                version=package["version"],
                source="dart pub deps --json",
            )
        )
    return sorted(set(packages))


def parse_gradle_plugins(root: Path) -> set[PackageQuery]:
    settings = root / "android" / "settings.gradle.kts"
    if not settings.exists():
        return set()

    text = settings.read_text(encoding="utf-8")
    plugin_coordinates = {
        "com.android.application": "com.android.tools.build:gradle",
        "org.jetbrains.kotlin.android": "org.jetbrains.kotlin:kotlin-gradle-plugin",
    }
    packages: set[PackageQuery] = set()
    for plugin_id, coordinate in plugin_coordinates.items():
        match = re.search(
            rf'id\("{re.escape(plugin_id)}"\)\s+version\s+"([^"]+)"',
            text,
        )
        if not match:
            continue
        packages.add(
            PackageQuery(
                ecosystem="Maven",
                name=coordinate,
                version=match.group(1),
                source=str(settings.relative_to(root)),
            )
        )
    return packages


def parse_gradle_runtime_packages(root: Path) -> set[PackageQuery]:
    gradlew = root / "android" / "gradlew"
    if not gradlew.exists():
        return set()

    output = run_command(
        [
            "./gradlew",
            "--quiet",
            ":app:dependencies",
            "--configuration",
            "debugRuntimeClasspath",
            "--console=plain",
        ],
        gradlew.parent,
    )
    packages: set[PackageQuery] = set()
    coordinate_pattern = re.compile(
        r"(?:\+---|\\---)\s+"
        r"([A-Za-z0-9_.-]+):([A-Za-z0-9_.-]+):([A-Za-z0-9_.+_-]+)"
        r"(?:\s+->\s+([A-Za-z0-9_.+_-]+))?"
    )
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.endswith("(c)"):
            continue
        match = coordinate_pattern.search(line)
        if not match:
            continue
        group, artifact, requested_version, resolved_version = match.groups()
        if group == "io.flutter":
            continue
        packages.add(
            PackageQuery(
                ecosystem="Maven",
                name=f"{group}:{artifact}",
                version=resolved_version or requested_version,
                source="Gradle debugRuntimeClasspath",
            )
        )
    return packages


def query_osv(packages: list[PackageQuery]) -> list[tuple[PackageQuery, list[dict]]]:
    if not packages:
        return []

    payload = {
        "queries": [
            {
                "package": {
                    "ecosystem": package.ecosystem,
                    "name": package.name,
                },
                "version": package.version,
            }
            for package in packages
        ]
    }
    request = urllib.request.Request(
        OSV_BATCH_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "realtime-translate-mobile-supply-chain-check/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError) as exc:
        raise CheckFailure(f"OSV query failed: {exc}") from exc

    results = data.get("results", [])
    if len(results) != len(packages):
        raise CheckFailure("OSV returned an unexpected result count.")

    vulnerable: list[tuple[PackageQuery, list[dict]]] = []
    for package, result in zip(packages, results):
        vulns = result.get("vulns") or []
        if vulns:
            vulnerable.append((package, vulns))
    return vulnerable


def path_is_scannable(path: Path, root: Path) -> bool:
    relative_parts = path.relative_to(root).parts
    if any(part in SKIP_DIR_NAMES for part in relative_parts):
        return False
    if path.suffix.lower() in BINARY_SUFFIXES:
        return False
    return path.is_file()


def scan_for_secrets(root: Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path_is_scannable(path, root):
            continue
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\x00" in raw:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue

        relative = path.relative_to(root)
        for line_number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in SECRET_PATTERNS.items():
                if pattern.search(line):
                    findings.append(f"{relative}:{line_number}: {label}")
    return findings


def check_android_permissions(root: Path) -> list[str]:
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        return []

    text = manifest.read_text(encoding="utf-8")
    permissions = sorted(
        set(
            re.findall(
                r"<uses-permission[^>]+android:name=\"([^\"]+)\"",
                text,
            )
        )
    )
    unexpected = [
        permission
        for permission in permissions
        if permission not in ALLOWED_ANDROID_PERMISSIONS
    ]
    if unexpected:
        formatted = "\n".join(f"  - {permission}" for permission in unexpected)
        raise CheckFailure(
            "Unexpected Android permission(s). Review least privilege and "
            f"document before allowing:\n{formatted}"
        )

    missing = sorted(REQUIRED_ANDROID_PERMISSIONS.difference(permissions))
    if missing:
        formatted = "\n".join(f"  - {permission}" for permission in missing)
        raise CheckFailure(
            "Missing product-critical Android permission(s) from "
            f"{manifest.relative_to(root)}:\n{formatted}\n"
            "The phone-only MVP needs RECORD_AUDIO for capture and INTERNET for "
            "the direct phone-to-OpenAI network path."
        )
    return permissions


def main() -> int:
    root = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
        ).strip()
    )
    os.chdir(root)

    print("Checking secret patterns...")
    secret_findings = scan_for_secrets(root)
    if secret_findings:
        print("\n".join(secret_findings))
        raise CheckFailure("Potential secret-like value found.")

    print("Reviewing Android permissions...")
    permissions = check_android_permissions(root)
    if permissions:
        for permission in permissions:
            print(f"  allowed: {permission}")
    else:
        print("  no Android permissions declared")

    print("Collecting Pub dependencies...")
    pub_packages = load_pub_packages(root)
    print(f"  hosted Pub packages: {len(pub_packages)}")

    print("Collecting Maven dependencies...")
    maven_packages = sorted(
        parse_gradle_plugins(root) | parse_gradle_runtime_packages(root)
    )
    print(f"  Maven packages: {len(maven_packages)}")

    packages = sorted(set(pub_packages + maven_packages))
    print(f"Querying OSV for {len(packages)} pinned package versions...")
    vulnerable = query_osv(packages)
    if vulnerable:
        for package, vulns in vulnerable:
            vuln_ids = ", ".join(vuln.get("id", "unknown") for vuln in vulns)
            print(
                f"{package.ecosystem} {package.name} {package.version}: "
                f"{vuln_ids}"
            )
        raise CheckFailure("OSV vulnerabilities found.")

    print("Supply-chain checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckFailure as exc:
        print(f"Supply-chain checks failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
