"""Inspect pinned public R1 inputs without installing or executing them.

Uses only Python's standard library. The receipt is static artifact evidence,
never a claim that a Host, Relay connection, or iOS build passed.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import tarfile
from urllib.request import urlopen

SERVER_COMMIT = "8f905b53d195a2c1ae29913d90eaacd40addeda9"
SOURCE_SHA256 = "0832aad10e439ad6c8a77a24860b614ac583fb5ba67062e2857ef753b5c431ce"
PACKAGES = (
    ("ds-harness-remote", "0.6.3", "sha512-gJHzDpU80WSV/JtVfevKjkR+4EcMUZ+zN40AmRbqkPrLD/95V1GVYDS803yAk4N8iw9uk6nfG+mDzN5vhuS3ig=="),
    ("@deepseek-ai/dsh", "0.2.2-rc.1", "sha512-ijR9UEVYkG15Q/Q79JzvzLBzQOQfc63VLr9n6flpwHPhr5IKn2UxthnSoto/P9l7qGd7pPvI1Ra6TW7LH3oKpg=="),
)


def verify_integrity(data, expected):
    actual = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode("ascii")
    if actual != expected:
        raise ValueError("Published archive integrity mismatch")


def archive_texts(data):
    # Read members in memory; never extract archive paths onto the filesystem.
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        return {
            member.name: archive.extractfile(member).read().decode("utf-8", errors="replace")
            for member in archive.getmembers()
            if member.isfile() and member.name.endswith((".js", ".ts", ".json", ".md"))
        }


def markers(files, needles):
    return {
        needle: [
            {"file": name, "line": index + 1}
            for name, text in files.items()
            for index, line in enumerate(text.splitlines())
            if needle in line
        ]
        for needle in needles
    }


def fetch(url):
    with urlopen(url, timeout=60) as response:
        return response.read()


def inspect(cache, offline=False):
    cache.mkdir(parents=True, exist_ok=True)
    receipt = {
        "schema": 1,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "offline-cache" if offline else "public-download",
        "packages": [],
        "runtimeCompatibility": "NOT_RUN",
        "iosBuild": "NOT_RUN",
        "serverImageDigest": None,
    }
    for name, version, integrity in PACKAGES:
        stem = name.replace("/", "_").replace("@", "")
        metadata_path = cache / (stem + "-registry.json")
        archive_path = cache / (stem + ".tgz")
        if not offline:
            metadata_path.write_bytes(fetch(f"https://registry.npmjs.org/{name}/{version}"))
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata["name"] != name or metadata["version"] != version:
            raise ValueError("Registry package identity mismatch")
        if metadata["dist"]["integrity"] != integrity:
            raise ValueError("Registry integrity differs from pinned input")
        url = metadata["dist"]["tarball"]
        if not url.startswith("https://registry.npmjs.org/"):
            raise ValueError("Unexpected package archive origin")
        if not offline:
            archive_path.write_bytes(fetch(url))
        data = archive_path.read_bytes()
        verify_integrity(data, integrity)
        files = archive_texts(data)
        package = json.loads(files["package/package.json"])
        if package["name"] != name or package["version"] != version:
            raise ValueError("Archive package identity mismatch")
        receipt["packages"].append({
            "name": name, "version": version, "tarball": url,
            "integrity": integrity, "integrityVerified": True,
            "sha256": hashlib.sha256(data).hexdigest(),
            "gitHead": metadata.get("gitHead"), "license": package.get("license"),
            "engines": package.get("engines"), "bin": package.get("bin"),
            "markers": markers(files, ["harness.remote.v3", "harness.transport.describe",
                                        "transport.relay.attach", "harnessSessionGeneration",
                                        "dsh plugin --profile web add -w", "/api/v1/auth/login"]),
        })
    source = cache / "server-source.tgz"
    source_url = f"https://codeload.github.com/liguobao/ds-harness-remote/tar.gz/{SERVER_COMMIT}"
    if not offline:
        source.write_bytes(fetch(source_url))
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise ValueError("Server source archive differs from pinned download; review before repinning")
    files = archive_texts(data)
    prefix = f"ds-harness-remote-{SERVER_COMMIT}/"
    gateway = files[prefix + "apps/server/src/gateway.ts"]
    receipt["server"] = {
        "commit": SERVER_COMMIT, "source": source_url, "sha256": SOURCE_SHA256,
        "version": json.loads(files[prefix + "apps/server/package.json"])["version"],
        "transportDeclaration": [line.strip() for line in gateway.splitlines()
                                 if line.startswith("const SUPPORTED_TRANSPORTS =")],
        "markers": markers({name: text for name, text in files.items()
                            if name.startswith(prefix + "apps/server/src/")},
                           ["/api/v1/auth/login", "relay.frame", "relay.attach"]),
    }
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=Path(".harness-tmp-ios-preflight"))
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = inspect(args.cache, args.offline)
    rendered = json.dumps(receipt, ensure_ascii=False, indent=2) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
