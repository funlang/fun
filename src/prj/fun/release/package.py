#!/usr/bin/env python3
# ============================================================
# package.py -- turn per-platform CI build stages into release assets.
#
# The regression workflow uploads a small stage directory per platform:
#
#   raw/<platform>/{funcmd, funcmd-safe, libtcc.so, *.dll, build-env.json}
#
# This script lays out the user-visible tree (binary + lib/ + licenses +
# capabilities.json), creates reproducible archives, and writes the release
# metadata: SHA256SUMS, capabilities.json, SBOM.cdx.json and RELEASE_NOTES.md.
#
# It runs on the packaging runner only. Platform-specific probing happens in
# each build job (see probe.sh / the Windows job), so nothing here executes a
# foreign binary.
#
# Usage:
#   package.py --raw raw --out dist --tag v9.5.5-nightly.20261104 \
#       --version 9.5.5 --commit <sha> --date 20261104 --channel nightly \
#       --repo-root . [--previous-tag v9.5.4] [--source-epoch <unix>]
# ============================================================
import argparse
import fnmatch
import hashlib
import json
import os
import shutil
import sys
import tarfile
import time
import zipfile
from pathlib import Path

UNIX_PLATFORMS = {
    "linux-x64",
    "linux-arm64",
    "linux-loongarch64",
    "macos-x64",
    "macos-arm64",
}
WIN_PLATFORMS = {"win-x64"}
SUPPORTED = UNIX_PLATFORMS | WIN_PLATFORMS

LICENSE_FILES = ["LICENSE", "LICENSE.custom", "LICENSE.dll"]
DOC_FILES = ["README.md", "SAFETY.zh.md"]
UNIX_INSTALLER = ["install.sh"]
WIN_INSTALLER = ["install.ps1", "install.cmd", "uninstall.ps1", "uninstall.cmd"]

# Build intermediates for the assembler tables. lib-asm-pro and lib-asm-a64
# embed only the compressed ``asm-list*.fd2.gz`` at parse time, so the editable
# ``.fd`` source and the prefix-packed ``.fd2`` are dead weight in a release
# (about 1.6 MB uncompressed per platform). They stay in the repository for
# fun/lib/tools/make-asm-list.fun.
PACKAGE_EXCLUDE_PATTERNS = ("asm-list*.fd", "asm-list*.fd2")


def is_build_intermediate(name):
    return any(fnmatch.fnmatchcase(name, pat) for pat in PACKAGE_EXCLUDE_PATTERNS)


def die(msg):
    print(f"package: error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_tree(src, dst, epoch):
    shutil.copytree(
        src,
        dst,
        ignore=lambda _dir, names: [n for n in names if is_build_intermediate(n)],
    )
    for p in dst.rglob("*"):
        if p.is_file():
            os.utime(p, (epoch, epoch))


def write_text(path, text, mode=0o644, epoch=0):
    path.write_text(text, encoding="utf-8")
    os.chmod(path, mode)
    os.utime(path, (epoch, epoch))


def build_platform(platform, raw_dir, layout_root, repo_root, meta, epoch):
    src = raw_dir / platform
    if not src.is_dir():
        die(f"missing stage directory {src}")

    is_win = platform in WIN_PLATFORMS
    # The build target is funcmd, but the user-facing binary is `fun` (matching
    # the documented command and fun.exe on Windows).
    src_exe = "funcmd.exe" if is_win else "funcmd"
    src_safe = "funcmd-safe.exe" if is_win else "funcmd-safe"
    exe = "fun.exe" if is_win else "fun"
    safe_exe = "fun-safe.exe" if is_win else "fun-safe"

    caps_path = src / "build-env.json"
    if caps_path.is_file():
        # Windows PowerShell may write UTF-8 with a BOM.
        caps = json.loads(caps_path.read_text(encoding="utf-8-sig"))
    else:
        caps = {"platform": platform, "notes": "capabilities were not recorded"}

    caps.update(
        {
            "platform": platform,
            "commit_sha": meta["commit"],
            "tag": meta["tag"],
            "version": meta["version"],
            "channel": meta["channel"],
            "date": meta["date"],
            "safe": (src / src_safe).is_file(),
            "safe_level": "strict",
            "libtcc_present": any(
                (src / name).is_file()
                for name in (
                    ("libtcc.dll",)
                    if is_win
                    else (("libtcc.dylib",) if platform.startswith("macos") else ("libtcc.so",))
                )
            ),
            "executables": ["fun/" + exe]
            + (["fun/" + safe_exe] if (src / src_safe).is_file() else []),
        }
    )
    caps.setdefault("notes", "")
    # Older stage files predate the probe field; every supported target has a
    # machine-code backend, so absence means "not recorded", not "no".
    caps.setdefault("asm", True)

    name = f"fun-{meta['tag']}-{platform}"
    dest = layout_root / name
    dest.mkdir(parents=True)
    # Mirror the repository's runtime folder: the executable, lib/, demo/,
    # demos/ and test/ live together under fun/. That makes the downloaded
    # tree self-describing and lets the shipped regression runner work without
    # a checkout.
    runtime = dest / "fun"
    runtime.mkdir()

    if not (src / src_exe).is_file():
        die(f"{platform}: missing {src_exe} in stage")
    shutil.copy2(src / src_exe, runtime / exe)
    os.chmod(runtime / exe, 0o755)
    os.utime(runtime / exe, (epoch, epoch))

    if caps["safe"]:
        shutil.copy2(src / src_safe, runtime / safe_exe)
        os.chmod(runtime / safe_exe, 0o755)
        os.utime(runtime / safe_exe, (epoch, epoch))

    # Windows users need the optional DLLs beside the exe. Copy whichever the
    # build produced; a missing one is reported in capabilities.json.
    if is_win:
        for dll in ("pcre3.dll", "ffi.dll", "libtcc.dll", "zlib.dll"):
            p = src / dll
            if p.is_file():
                shutil.copy2(p, runtime / dll)
                os.utime(runtime / dll, (epoch, epoch))
    else:
        tcc_names = ("libtcc.dylib",) if platform.startswith("macos") else ("libtcc.so",)
        for tcc_name in tcc_names:
            tcc = src / tcc_name
            if tcc.is_file():
                shutil.copy2(tcc, runtime / tcc_name)
                os.chmod(runtime / tcc_name, 0o755)
                os.utime(runtime / tcc_name, (epoch, epoch))

    # The interpreter resolves the standard library next to the executable,
    # so lib/ must sit inside fun/. demo/demos/test are the same tree users
    # see in the repository and make the download independently verifiable.
    for sub in ("lib", "demo", "demos", "test"):
        p = repo_root / "fun" / sub
        if p.is_dir():
            copy_tree(p, runtime / sub, epoch)
    for ini in sorted((repo_root / "fun").glob("key_*.ini")):
        shutil.copy2(ini, runtime / ini.name)
        os.utime(runtime / ini.name, (epoch, epoch))

    for f in LICENSE_FILES + DOC_FILES:
        p = repo_root / f
        if p.is_file():
            shutil.copy2(p, dest / f)
            os.utime(dest / f, (epoch, epoch))

    write_text(
        dest / "capabilities.json",
        json.dumps(caps, indent=2, sort_keys=True) + "\n",
        epoch=epoch,
    )

    notes = [
        f"Fun {meta['tag']} ({meta['channel']}) for {platform}",
        f"commit {meta['commit']}",
        "",
        "Run:        ./fun/" + exe + " --help",
        "Safe build: ./fun/" + safe_exe if caps["safe"] else "Safe build: not included",
        "",
        "regex: " + ("yes" if caps.get("regex") else "NO"),
        "getapi/FFI: " + ("yes" if caps.get("ffi") else "NO"),
        "runtime C compile (libtcc): " + ("yes" if caps.get("tcc") else "NO"),
        "",
        "fun (built from funcmd.dpr) is MIT (LICENSE). The embedded fun.dll product is licensed",
        "separately (LICENSE.dll) and is NOT part of this archive.",
    ]
    if is_win:
        notes += [
            "",
            "Keep the .dll files in fun/ next to fun.exe.",
            "Install: extract this archive and double-click install.cmd.",
            "It installs to %LOCALAPPDATA%\\Programs\\Fun, adds <dir>\\fun to",
            "PATH, registers .fun/.foo/.fxx, and adds an Apps & Features entry.",
            "Use install.cmd -AllUsers (elevated), -Dir DIR, -NoPath, -NoAssoc",
            "or -Portable for other layouts. uninstall.cmd reverses it.",
            "",
            "This is an unsigned 7z archive: Windows SmartScreen may warn. Use",
            "7-Zip (or another extractor that does not add Mark-of-the-Web).",
        ]
    elif platform == "linux-loongarch64":
        notes += [
            "",
            "Keep lib/ next to fun/fun.",
            "Install this extracted tree: ./install.sh --local",
            "(adds a fun symlink under ~/.local/bin; pass --add-path to append",
            "that directory to a shell profile). Without --local it downloads",
            "the newest release instead.",
            "This target has no libtcc (runtime C) or native asm backend;",
            "the full build still provides regex and getapi/FFI.",
            "It uses the platform loader /lib64/ld-linux-loongarch-lp64d.so.1;",
            "install libpcre.so.1 and libffi.so.8 from your distribution if",
            "the interpreter reports that they are missing.",
            "Run the shipped suite with: fun/test/run-linux-regression.sh",
        ]
    else:
        notes += [
            "",
            "Keep lib/ and libtcc.so (libtcc.dylib on macOS) next to fun/fun.",
            "Install this extracted tree: ./install.sh --local",
            "(adds a fun symlink under ~/.local/bin; pass --add-path to append",
            "that directory to a shell profile). Without --local it downloads",
            "the newest release instead.",
            "Run the shipped suite with: fun/test/run-linux-regression.sh",
        ]
    if meta["channel"] == "nightly":
        notes += ["", "This is a nightly prerelease: it may be replaced or deleted."]
    if platform.startswith("macos"):
        notes += [
            "",
            "macOS builds are unsigned and not notarized; Gatekeeper may warn.",
            "Use install.sh (curl downloads are not quarantined) or clear the",
            "attribute yourself: xattr -dr com.apple.quarantine <dir>",
        ]
    write_text(dest / "RUNNING.txt", "\n".join(notes) + "\n", epoch=epoch)

    # Ship the installer next to the runtime tree, so an extracted archive is
    # self-installing on every platform. On macOS install.sh is also the
    # supported way to avoid Gatekeeper without code signing.
    installer_files = WIN_INSTALLER if is_win else UNIX_INSTALLER
    for installer_name in installer_files:
        p = repo_root / installer_name
        if not p.is_file():
            die(f"missing installer file {installer_name}")
        shutil.copy2(p, dest / installer_name)
        if installer_name.endswith(".sh"):
            os.chmod(dest / installer_name, 0o755)
        os.utime(dest / installer_name, (epoch, epoch))

    # Normalize every entry, including directories, after all copies. tar
    # stores directory mtimes and 7z reads them from the filesystem; leaving
    # them at the current time makes two runs of the same inputs differ.
    for p in [dest] + list(dest.rglob("*")):
        os.utime(p, (epoch, epoch))

    if is_win:
        archive = layout_root / (name + ".7z")
        make_7z(dest, archive)
    elif platform.startswith("macos"):
        archive = layout_root / (name + ".zip")
        make_zip(dest, archive, epoch)
    else:
        archive = layout_root / (name + ".tar.gz")
        make_tar(dest, archive, epoch)
    if not archive.is_file():
        die(f"{platform}: archive was not created: {archive}")
    os.utime(archive, (epoch, epoch))
    return caps, archive


def make_tar(src_dir, out, epoch):
    def norm(ti):
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = "root"
        ti.mtime = epoch
        if ti.isdir():
            ti.mode = 0o755
        elif ti.mode & 0o111:
            ti.mode = 0o755
        else:
            ti.mode = 0o644
        return ti

    import gzip

    # Write the tar uncompressed, then gzip it with an explicit mtime and an
    # empty stored name. Passing mtime to tarfile.open is not portable across
    # the Python versions the runners use, and without it the gzip header makes
    # every run produce a different checksum.
    raw = out.with_name(out.name + ".tar")
    with tarfile.open(raw, "w") as tf:
        tf.add(src_dir, arcname=src_dir.name, recursive=True, filter=norm)
    with open(raw, "rb") as fi, open(out, "wb") as fo:
        with gzip.GzipFile(filename="", mode="wb", compresslevel=9,
                           fileobj=fo, mtime=epoch) as gz:
            shutil.copyfileobj(fi, gz)
    raw.unlink()


def make_zip(src_dir, out, epoch):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(src_dir.rglob("*")):
            arc = str(Path(src_dir.name) / p.relative_to(src_dir)).replace(os.sep, "/")
            if p.is_dir():
                continue
            info = zipfile.ZipInfo(arc, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if (p.suffix == ".exe" or os.access(p, os.X_OK)) else 0o644
            info.external_attr = (mode & 0xFFFF) << 16
            info.create_system = 3  # UNIX, so the mode bits mean something
            zf.writestr(info, p.read_bytes())


def make_7z(src_dir, out):
    import subprocess

    seven = shutil.which("7z") or shutil.which("7zz") or shutil.which("7za")
    if not seven:
        die("7z not found; install p7zip-full so Windows assets can be .7z")
    # -t7z: real 7z container (smaller, and extraction does not mark the exe
    # with Mark-of-the-Web the way a browser-downloaded zip can).
    subprocess.run([seven, "a", "-t7z", "-mx=9", str(out.resolve()), src_dir.name],
                   cwd=str(src_dir.parent), check=True,
                   stdout=subprocess.DEVNULL)


def git_tag_message(repo_root, tag):
    """Read the annotated tag body; empty for a lightweight tag."""
    import subprocess

    try:
        out = subprocess.run(
            ["git", "for-each-ref", f"refs/tags/{tag}",
             "--format=%(contents)"],
            cwd=str(repo_root), check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        ).stdout.strip()
        return out
    except Exception:
        return ""


def git_log(repo_root, previous, commit, limit=40):
    import subprocess

    if not previous:
        return []
    try:
        out = subprocess.run(
            ["git", "log", "--oneline", "--no-decorate",
             f"-{limit}", f"{previous}..{commit}"],
            cwd=str(repo_root), check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        ).stdout.strip()
        return [line for line in out.splitlines() if line]
    except Exception:
        return []


def sbom(meta, caps_list):
    libs = [
        {
            "type": "framework",
            "name": "Free Pascal",
            "version": "3.2.2",
            "purl": "pkg:generic/freepascal@3.2.2",
            "licenses": [{"license": {"name": "GPL-2.0-or-later with linking exception"}}],
        }
    ]
    if any(c.get("regex") for c in caps_list):
        libs.append(
            {
                "type": "library",
                "name": "PCRE",
                "version": "8.45",
                "purl": "pkg:generic/pcre@8.45",
                "licenses": [{"license": {"id": "BSD-3-Clause"}}],
            }
        )
    if any(c.get("tcc") or c.get("libtcc_present") for c in caps_list):
        libs.append(
            {
                "type": "library",
                "name": "Tiny C Compiler",
                "version": "0.9.27",
                "purl": "pkg:generic/tcc@0.9.27",
                "licenses": [{"license": {"id": "LGPL-2.1-only"}}],
            }
        )
    if any(c.get("zlib_present") for c in caps_list):
        libs.append(
            {
                "type": "library",
                "name": "zlib",
                "version": "1.2.11",
                "purl": "pkg:generic/zlib@1.2.11",
                "licenses": [{"license": {"id": "Zlib"}}],
            }
        )
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "component": {
                "type": "application",
                "name": "fun",
                "version": meta["version"],
                "purl": f"pkg:github/funlang/fun@{meta['commit']}",
            },
            "properties": [
                {"name": "fun:tag", "value": meta["tag"]},
                {"name": "fun:channel", "value": meta["channel"]},
            ],
        },
        "components": libs,
    }


def notes(meta, caps_list, archives, repo_root, previous):
    lines = []
    lines += [
        f"## Fun {meta['tag']}",
        "",
        "### Downloads",
        "",
        "| Platform | Archive |",
        "| --- | --- |",
    ]
    # Direct links first: a release page should not require scrolling to the
    # bottom to install. Names match the uploaded assets.
    base = f"https://github.com/funlang/fun/releases/download/{meta['tag']}"
    for c, a in zip(caps_list, archives):
        lines.append(f"| {c['platform']} | [`{a.name}`]({base}/{a.name}) |")
    lines += [
        f"| macOS / Linux | [`install.sh`]({base}/install.sh) |",
        "| Windows | extract the `.7z`, then run `install.cmd` |",
        "",
        f"_{meta['channel']} · `{meta['commit'][:12]}` · {meta['date']} (UTC+8)_",
        "",
    ]

    if meta["channel"] == "nightly":
        lines += [
            "Nightly prerelease; `releases/latest` still points at the stable build.",
            "",
        ]
        commits = git_log(repo_root, previous, meta["commit"], limit=12)
        if commits:
            lines += ["### Changes", ""]
            lines += [f"- {c}" for c in commits]
            lines += [""]
    else:
        body = git_tag_message(repo_root, meta["tag"])
        if body:
            lines += ["### Changes", "", body, ""]

    lines += [
        "### Capabilities",
        "",
        "| platform | regex | FFI | runtime C (tcc) | asm | safe build | notes |",
        "|---|---|---|---|---|---|---|",
    ]
    for c in caps_list:
        mark = lambda v: "yes" if v else "no"
        note = (c.get("notes") or "").replace("|", "/").strip()
        lines.append(
            f"| {c['platform']} | {mark(c.get('regex'))} | {mark(c.get('ffi'))} | "
            f"{mark(c.get('tcc'))} | {mark(c.get('asm', True))} | "
            f"{mark(c.get('safe'))} | {note} |"
        )
    lines += [
        "",
        "The first five columns describe the default binary. `safe build` is the",
        "separate capability-restricted `fun-safe` binary (strict level).",
        "`capabilities.json` in each archive is the machine-readable table.",
        "",
        "Verify with `sha256sum -c SHA256SUMS` (Linux/macOS) or",
        "`Get-FileHash` (Windows).",
        "Windows `.7z` and macOS `.zip` assets are unsigned; SmartScreen or",
        "Gatekeeper may warn. Run `./install.sh --local` from an extracted",
        "macOS/Linux archive or `install.cmd` on Windows so PATH and file",
        "associations are registered for you.",
        "",
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--date", required=True)
    ap.add_argument("--channel", required=True, choices=["nightly", "stable"])
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--previous-tag", default="")
    ap.add_argument("--source-epoch", type=int, default=0)
    args = ap.parse_args()

    raw = Path(args.raw)
    out = Path(args.out)
    repo_root = Path(args.repo_root).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    layout_root = out / "_layout"
    layout_root.mkdir()

    meta = {
        "tag": args.tag,
        "version": args.version,
        "commit": args.commit,
        "date": args.date,
        "channel": args.channel,
    }
    epoch = args.source_epoch

    platforms = sorted(p.name for p in raw.iterdir() if p.is_dir() and p.name in SUPPORTED)
    if not platforms:
        die(f"no supported platform stages under {raw}")

    caps_list, archives = [], []
    for platform in platforms:
        caps, archive = build_platform(platform, raw, layout_root, repo_root, meta, epoch)
        caps_list.append(caps)
        archives.append(archive)
        print(f"package: {archive.name} ({archive.stat().st_size} bytes)")

    # Archives are built inside _layout so their top-level directory name is
    # stable; move them to the release root before that directory is removed.
    moved = []
    for archive in archives:
        target = out / archive.name
        shutil.move(str(archive), str(target))
        moved.append(target)
    archives = moved

    # Aggregate, stable ordering.
    caps_list.sort(key=lambda c: c["platform"])
    aggregate = {
        "tag": meta["tag"],
        "version": meta["version"],
        "commit": meta["commit"],
        "date": meta["date"],
        "channel": meta["channel"],
        "platforms": caps_list,
    }
    write_text(out / "capabilities.json",
               json.dumps(aggregate, indent=2, sort_keys=True) + "\n", epoch=epoch)
    write_text(out / "SBOM.cdx.json",
               json.dumps(sbom(meta, caps_list), indent=2) + "\n", epoch=epoch)
    write_text(out / "RELEASE_NOTES.md",
               notes(meta, caps_list, archives, repo_root, args.previous_tag) + "\n",
               epoch=epoch)

    # Build provenance in a simple, greppable form too.
    write_text(
        out / "BUILD-INFO.txt",
        f"tag={meta['tag']}\nversion={meta['version']}\ncommit={meta['commit']}\n"
        f"date={meta['date']}\nchannel={meta['channel']}\n",
        epoch=epoch,
    )

    install = repo_root / "install.sh"
    if install.is_file():
        shutil.copy2(install, out / "install.sh")
        os.chmod(out / "install.sh", 0o755)
        os.utime(out / "install.sh", (epoch, epoch))

    lines = []
    for archive in sorted(archives, key=lambda p: p.name):
        lines.append(f"{sha256_file(archive)}  {archive.name}")
    if (out / "install.sh").is_file():
        lines.append(f"{sha256_file(out / 'install.sh')}  install.sh")
    write_text(out / "SHA256SUMS", "\n".join(lines) + "\n", epoch=epoch)

    # Keep only the public assets plus the metadata.
    shutil.rmtree(layout_root)
    print(f"package: {len(archives)} archives, {len(caps_list)} platforms")


if __name__ == "__main__":
    main()
