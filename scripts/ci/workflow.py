#!/usr/bin/env python3
import os
import sys
import subprocess
import datetime
from pathlib import Path
import time
import json


# REPO ROOT relative to script dir
ROOT = Path(__file__).resolve().parents[2]

# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------

def run(cmd, check=True, cwd=None):
    wd = cwd if cwd is not None else ROOT
    print(f"$ {cmd}", flush=True, file=sys.stderr)
    subprocess.run(
        cmd,
        shell=True,
        cwd=wd,
        check=check,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )
    print("", flush=True, file=sys.stderr)

def runAndGet(cmd, cwd=None):
    wd = cwd if cwd is not None else ROOT
    print(f"$ {cmd}", flush=True, file=sys.stderr)
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=wd,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        check=True,
    )
    out = result.stdout.strip()
    print(out, flush=True, file=sys.stderr)
    print("", flush=True, file=sys.stderr)
    return out

def getenv(name, default=""):
    return os.environ.get(name, default)

# ----------------------------------------------------------
# SHARED
# ----------------------------------------------------------

def short_commit():
    return runAndGet("git rev-parse --short HEAD")

# ----------------------------------------------------------
# BUILD NUMBER RESERVATION
# ----------------------------------------------------------

def reserve_build_number(repo, max_attempts=5):
    repo = Path(repo).resolve()
    version_json = repo / "version.json"

    def utc_now():
        return datetime.datetime.now(datetime.UTC)\
            .strftime("%Y-%m-%dT%H:%M:%SZ")

    def read():
        if not version_json.exists():
            return {"build": 0, "issued_at": utc_now()}
        return json.loads(version_json.read_text())

    def write(data):
        version_json.write_text(json.dumps(data, indent=2) + "\n")

    for _ in range(max_attempts):
        run("git fetch --depth=1 origin HEAD", check=False, cwd=repo)
        run("git reset --hard FETCH_HEAD", check=False, cwd=repo)

        data = read()
        data["build"] += 1
        data["issued_at"] = utc_now()

        write(data)

        run("git add version.json", check=False, cwd=repo)
        run(
            f"git commit -m '{data['tag']} - build no: {data['build']}' || true",
            check=False,
            cwd=repo,
        )

        rc = subprocess.call("git push", shell=True, cwd=repo)

        if rc == 0:
            print(f"Reserved build #{data['build']}", file=sys.stderr)
            return data["build"]

        print("Push rejected, retrying...", file=sys.stderr)
        time.sleep(2)

    raise SystemExit("Failed reserving build number")

# ----------------------------------------------------------
# MARKETING VERSION
# ----------------------------------------------------------

def get_marketing_version():
    return runAndGet("grep MARKETING_VERSION Build.xcconfig | sed -e 's/MARKETING_VERSION = //g'")

def set_marketing_version(qualified):
    run(
        f"sed -E "
        f"'s/^MARKETING_VERSION = .*/MARKETING_VERSION = {qualified}/' "
        f"-i '' {ROOT}/Build.xcconfig"
    )

def compute_qualified_version(marketing, build_num, channel, short):
    date = datetime.datetime.now(datetime.UTC).strftime("%Y.%m.%d")
    return f"{marketing}-{channel}.{date}.{build_num}+{short}"

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

def is_sim_booted(model):
    out = runAndGet(f'xcrun simctl list devices "{model}"')
    return "Booted" in out

def boot_sim_async(model):
    log = ROOT / "build/logs/tests-run.log"
    log.parent.mkdir(parents=True, exist_ok=True)

    if is_sim_booted(model):
        run(f'echo "Simulator {model} already booted." | tee -a {log}')
        return

    run(f'echo "Booting simulator {model} asynchronously..." | tee -a {log}')

    with open(log, "a") as f:
        subprocess.Popen(
            ["xcrun", "simctl", "boot", model],
            cwd=ROOT,
            stdout=f,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

def boot_sim_sync(model):
    run("mkdir -p build/logs")

    for i in range(1, 7):
        if is_sim_booted(model):
            run('echo "Simulator booted." | tee -a build/logs/tests-run.log')
            return

        run(f'echo "Simulator not ready (attempt {i}/6), retrying in 10s..." | tee -a build/logs/tests-run.log')
        time.sleep(10)

    raise SystemExit("Simulator failed to boot")

def tests_run(model):
    run("mkdir -p build/logs")

    if not is_sim_booted(model):
        boot_sim_sync(model)

    run("make run-tests 2>&1 | tee -a build/logs/tests-run.log")
    run("zip -r -9 ./test-results.zip ./build/tests")

# ----------------------------------------------------------
# LOG ENCRYPTION
# ----------------------------------------------------------

def encrypt_logs(name):
    default_pwd = "12345"
    pwd = getenv("BUILD_LOG_ZIP_PASSWORD", default_pwd)

    if pwd == default_pwd:
        print("Warning: BUILD_LOG_ZIP_PASSWORD not set, using fallback password", file=sys.stderr)

    run(f'cd build/logs && zip -e -P "{pwd}" ../../{name}.zip *')

# ----------------------------------------------------------
# RELEASE NOTES
# ----------------------------------------------------------

def release_notes(tag):
    run(
        f"python3 generate_release_notes.py "
        f"{tag} "
        f"--repo-root {ROOT} "
        f"--output-dir {ROOT}"
    )

# ----------------------------------------------------------
# DEPLOY SOURCE.JSON
# ----------------------------------------------------------

def deploy(repo, source_json, release_tag, short_commit, marketing_version, version, channel, bundle_id, ipa_name):
    repo = Path(repo).resolve()
    ipa_path = ROOT / ipa_name

    if not repo.exists():
        raise SystemExit(f"{repo} repo missing")

    if not ipa_path.exists():
        raise SystemExit(f"{ipa_path} missing")

    run(f"pushd {repo}", check=True)
    try:
        # source_json is RELATIVE to repo
        if not Path(source_json).exists():
            raise SystemExit(f"{source_json} missing inside repo")

        run(
            f"python3 {ROOT}/generate_source_metadata.py "
            f"--repo-root {ROOT} "
            f"--ipa {ipa_path} "
            f"--output-dir . "
            f"--release-notes-dir . "
            f"--release-tag {release_tag} "
            f"--version {version} "
            f"--marketing-version {marketing_version} "
            f"--short-commit {short_commit} "
            f"--release-channel {channel} "
            f"--bundle-id {bundle_id}"
        )

        run("git config user.name 'GitHub Actions'", check=False)
        run("git config user.email 'github-actions@github.com'", check=False)

        run(f"python3 {ROOT}/scripts/update_source_metadata.py '{source_json}'")

        max_attempts = 5
        for attempt in range(1, max_attempts + 1):
            run("git fetch --depth=1 origin HEAD", check=False)
            run("git reset --hard FETCH_HEAD", check=False)

            # regenerate after reset so we don't lose changes
            run(f"python3 {ROOT}/scripts/update_source_metadata.py '{source_json}'")
            run(f"git add --verbose {source_json}", check=False)
            run(f"git commit -m '{release_tag} - deployed {version}' || true", check=False)

            rc = subprocess.call("git push", shell=True)

            if rc == 0:
                print("Deploy push succeeded", file=sys.stderr)
                break

            print(f"Push rejected (attempt {attempt}/{max_attempts}), retrying...", file=sys.stderr)
            time.sleep(0.5)
        else:
            raise SystemExit("Deploy push failed after retries")

    finally:
        run("popd", check=False)

# ----------------------------------------------------------
# ENTRYPOINT
# ----------------------------------------------------------

COMMANDS = {
    # ----------------------------------------------------------
    # SHARED
    # ----------------------------------------------------------
    "commid-id"               : (short_commit,              0, ""),

    # ----------------------------------------------------------
    # VERSION / MARKETING
    # ----------------------------------------------------------
    "get-marketing-version"   : (get_marketing_version,     0, ""),
    "set-marketing-version"   : (set_marketing_version,     1, "<qualified_version>"),
    "compute-qualified"       : (compute_qualified_version, 4, "<marketing> <build_num> <channel> <short_commit>"),
    "reserve_build_number"    : (reserve_build_number,      1, "<repo>"),

    # ----------------------------------------------------------
    # CLEAN
    # ----------------------------------------------------------
    "clean"                   : (clean,                     0, ""),
    "clean-derived-data"      : (clean_derived_data,        0, ""),
    "clean-spm-cache"         : (clean_spm_cache,           0, ""),

    # ----------------------------------------------------------
    # BUILD
    # ----------------------------------------------------------
    "build"                   : (build,                     0, ""),

    # ----------------------------------------------------------
    # TESTS
    # ----------------------------------------------------------
    "tests-build"             : (tests_build,               0, ""),
    "tests-run"               : (tests_run,                 1, "<model>"),
    "boot-sim-async"          : (boot_sim_async,            1, "<model>"),
    "boot-sim-sync"           : (boot_sim_sync,             1, "<model>"),

    # ----------------------------------------------------------
    # LOG ENCRYPTION
    # ----------------------------------------------------------
    "encrypt-build"           : (lambda: encrypt_logs("encrypted-build-logs"),        0, ""),
    "encrypt-tests-build"     : (lambda: encrypt_logs("encrypted-tests-build-logs"),  0, ""),
    "encrypt-tests-run"       : (lambda: encrypt_logs("encrypted-tests-run-logs"),    0, ""),

    # ----------------------------------------------------------
    # RELEASE / DEPLOY
    # ----------------------------------------------------------
    "release-notes"           : (release_notes,             1, "<tag>"),
    "deploy"                  : (deploy,                    9, "<repo> <source_json> <release_tag> <short_commit> <marketing_version> <version> <channel> <bundle_id> <ipa_name>"),
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