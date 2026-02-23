#!/usr/bin/env python3
import os
import sys
import subprocess
import datetime
from pathlib import Path

# REPO ROOT relative to script dir
ROOT = Path(__file__).resolve().parents[2]


# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------

def run(cmd, check=True):
    print(f"$ {cmd}", flush=True)
    subprocess.run(cmd, shell=True, cwd=ROOT, check=check)
    print("", flush=True)


def getenv(name, default=""):
    return os.environ.get(name, default)


# ----------------------------------------------------------
# SHARED
# ----------------------------------------------------------

def short_commit():
    sha = subprocess.check_output(
        "git rev-parse --short HEAD",
        shell=True,
        cwd=ROOT
    ).decode().strip()
    return sha


# ----------------------------------------------------------
# VERSION BUMP
# ----------------------------------------------------------

def bump_beta():
    date = datetime.datetime.now(datetime.UTC).strftime("%Y.%m.%d")
    release_channel = getenv("RELEASE_CHANNEL", "beta")
    build_file = ROOT / "build_number.txt"

    short = subprocess.check_output(
        "git rev-parse --short HEAD",
        shell=True,
        cwd=ROOT
    ).decode().strip()

    def write(num):
        run(
            f"""sed -e "/MARKETING_VERSION = .*/s/$/-{release_channel}.{date}.{num}+{short}/" -i '' {ROOT}/Build.xcconfig"""
        )
        build_file.write_text(f"{date},{num}")

    if not build_file.exists():
        write(1)
        return

    last = build_file.read_text().strip().split(",")[1]
    write(int(last) + 1)


# ----------------------------------------------------------
# VERSION EXTRACTION
# ----------------------------------------------------------

def extract_version():
    v = subprocess.check_output(
        "grep MARKETING_VERSION Build.xcconfig | sed -e 's/MARKETING_VERSION = //g'",
        shell=True,
        cwd=ROOT
    ).decode().strip()
    return v


# ----------------------------------------------------------
# CLEAN
# ----------------------------------------------------------
def clean():
    run("make clean")

def clean_derived_data():
    run("rm -rf ~/Library/Developer/Xcode/DerivedData/*", check=False)

def clean_spm_cache():
    run("rm -rf ~/Library/Caches/org.swift.swiftpm/*", check=False)

# ----------------------------------------------------------
# BUILD
# ----------------------------------------------------------

def build():
    run("make clean")
    run("rm -rf ~/Library/Developer/Xcode/DerivedData/*", check=False)
    run("mkdir -p build/logs")

    run(
        "set -o pipefail && "
        "NSUnbufferedIO=YES make -B build "
        "2>&1 | tee -a build/logs/build.log | xcbeautify --renderer github-actions"
    )

    run("make fakesign | tee -a build/logs/build.log")
    run("make ipa | tee -a build/logs/build.log")

    run("zip -r -9 ./SideStore.dSYMs.zip ./SideStore.xcarchive/dSYMs")


# ----------------------------------------------------------
# TESTS BUILD
# ----------------------------------------------------------

def tests_build():
    run("mkdir -p build/logs")
    run(
        "NSUnbufferedIO=YES make -B build-tests "
        "2>&1 | tee -a build/logs/tests-build.log | xcbeautify --renderer github-actions"
    )


# ----------------------------------------------------------
# TESTS RUN
# ----------------------------------------------------------

def tests_run():
    run("mkdir -p build/logs")
    run("nohup make -B boot-sim-async </dev/null >> build/logs/tests-run.log 2>&1 &")

    run("make -B sim-boot-check | tee -a build/logs/tests-run.log")

    run("make run-tests 2>&1 | tee -a build/logs/tests-run.log")

    run("zip -r -9 ./test-results.zip ./build/tests")


# ----------------------------------------------------------
# LOG ENCRYPTION
# ----------------------------------------------------------

def encrypt_logs(name):
    pwd = getenv("BUILD_LOG_ZIP_PASSWORD", "12345")
    run(
        f'cd build/logs && zip -e -P "{pwd}" ../../{name}.zip *'
    )


# ----------------------------------------------------------
# RELEASE NOTES
# ----------------------------------------------------------
def release_notes(tag):
    run(f"python3 generate_release_notes.py {tag}")


# ----------------------------------------------------------
# PUBLISH SOURCE.JSON
# ----------------------------------------------------------
def publish_apps(release_tag, short_commit):
    repo = ROOT / "Dependencies/apps-v2.json"

    if not repo.exists():
        raise SystemExit("Dependencies/apps-v2.json repo missing")

    # generate metadata + release notes
    run(
        f"python3 generate_source_metadata.py "
        f"--release-tag {release_tag} "
        f"--short-commit {short_commit}"
    )

    # update source.json using generated metadata
    run("pushd Dependencies/apps-v2.json", check=False)

    run("git config user.name 'GitHub Actions'", check=False)
    run("git config user.email 'github-actions@github.com'", check=False)

    run("python3 ../../scripts/update_source_metadata.py './_includes/source.json'")

    run("git add --verbose ./_includes/source.json", check=False)
    run(f"git commit -m ' - updated for {short_commit} deployment' || true",check=False)
    run("git push --verbose", check=False)

    run("popd", check=False)
    
# ----------------------------------------------------------
# ENTRYPOINT
# ----------------------------------------------------------
COMMANDS = {
    "commid-id"          : (short_commit,        0, ""),
    "bump-beta"          : (bump_beta,           0, ""),
    "version"            : (extract_version,     0, ""),
    "clean"              : (clean,               0, ""),
    "clean-derived-data" : (clean_derived_data,  0, ""),
    "clean-spm-cache"    : (clean_spm_cache,     0, ""),
    "build"              : (build,               0, ""),
    "tests-build"        : (tests_build,         0, ""),
    "tests-run"          : (tests_run,           0, ""),
    "encrypt-build"      : (lambda: encrypt_logs("encrypted-build-logs"),       0, ""),
    "encrypt-tests-build": (lambda: encrypt_logs("encrypted-tests-build-logs"), 0, ""),
    "encrypt-tests-run"  : (lambda: encrypt_logs("encrypted-tests-run-logs"),   0, ""),
    "release-notes"      : (release_notes,       1, "<tag>"),
    "deploy"             : (publish_apps,        2, "<release_tag> <short_commit>"),
}

def main():
    def usage():
        lines = ["Available commands:"]
        for name, (_, argc, arg_usage) in COMMANDS.items():
            suffix = f" {arg_usage}" if arg_usage else ""
            lines.append(f"  - {name}{suffix}")
        return "\n".join(lines)

    if len(sys.argv) < 2:
        raise SystemExit(usage())

    cmd = sys.argv[1]

    if cmd not in COMMANDS:
        raise SystemExit(
            f"Unknown command '{cmd}'.\n\n{usage()}"
        )

    func, argc, arg_usage = COMMANDS[cmd]

    if len(sys.argv) - 2 < argc:
        suffix = f" {arg_usage}" if arg_usage else ""
        raise SystemExit(f"Usage: workflow.py {cmd}{suffix}")

    args = sys.argv[2:2 + argc]
    func(*args) if argc else func()


if __name__ == "__main__":
    main()