import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


repo = Path(__file__).resolve().parents[1]
fixture = tempfile.TemporaryDirectory(prefix="omadev-target-check-")
base = Path(fixture.name)
home = base / "home"
root = base / "project with spaces"
bin_dir = base / "bin"
for directory in (home, root, bin_dir, base / "runtime"):
    directory.mkdir()
env = os.environ | {
    "HOME": str(home),
    "XDG_STATE_HOME": str(base / "state"),
    "XDG_RUNTIME_DIR": str(base / "runtime"),
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "PATH": str(bin_dir) + ":" + os.environ["PATH"],
}


def executable(name, content):
    path = bin_dir / name
    path.write_text("#!/bin/sh\n" + content)
    path.chmod(0o755)
    return path


# The validator deliberately rejects a root symlink, as native Omarchy does.
executable("omarchy", '''
[ "$1" = plugin ] && [ "$2" = validate ] && [ ! -L "$3" ] &&
  jq -e 'has("id")' "$3/manifest.json" >/dev/null
''')
executable("omarchy-git-url-check", '''
case "$1" in
  file://*|https://github.com/fixture/plugin.git) exit 0;;
  *) exit 1;;
esac
''')
executable("omarchy-shell", 'printf rescan >> "$HOME/rescans"\n')


def run(*argv, good=True):
    result = subprocess.run(
        [str(arg) for arg in argv], env=env, text=True, capture_output=True,
    )
    if good:
        assert result.returncode == 0, (argv, result.stdout, result.stderr)
    return result


manifest = {
    "schemaVersion": 1,
    "id": "io.test.target",
    "name": "Target",
    "version": "0.1.0",
    "kinds": ["service"],
    "entryPoints": {"service": "Main.qml"},
}
(root / "manifest.json").write_text(json.dumps(manifest))
(root / "Main.qml").write_text("import QtQml\nQtObject {}\n")
(root / ".omarchy-plugin-dev").mkdir()
config = root / ".omarchy-plugin-dev/task-config.json"
config.write_text('{"version":2,"builds":[]}\n')
run("git", "init", "-b", "main", root)
run("git", "-C", root, "config", "user.email", "test@example.org")
run("git", "-C", root, "config", "user.name", "test")
run("git", "-C", root, "add", "manifest.json", "Main.qml")
run("git", "-C", root, "commit", "-m", "first")
run("git", "-C", root, "tag", "v1")
first = run("git", "-C", root, "rev-parse", "HEAD").stdout.strip()
(root / "Main.qml").write_text("import QtQml\nQtObject { property int value: 2 }\n")
run("git", "-C", root, "commit", "-am", "second")
remote = base / "remote.git"
run("git", "clone", "--bare", root, remote)
url = remote.as_uri()
destination = home / ".config/omarchy/plugins/io.test.target"


def request(kind="symlink", source=None, dest=None, ref=None):
    entry = {
        "name": kind,
        "type": kind,
        "source": source or str(root),
        "destination": str(dest or destination),
        "tasks": {},
    }
    if ref:
        entry["ref"] = ref
    return {
        "project": str(root),
        "id": manifest["id"],
        "entry": entry,
        "protected": [str(root)],
        "config_hash": hashlib.sha256(config.read_bytes()).hexdigest(),
    }


def inspect(req, good=True):
    result = run(repo / "scripts/prepare-target", "inspect", json.dumps(req), good=good)
    return json.loads(result.stdout) if good else result


def prepare(req, approve=False, good=True):
    req = req | {"expected": inspect(req), "delete_approved": approve}
    return run(repo / "scripts/prepare-target", "prepare", json.dumps(req), good=good)


def stamp(path):
    stat = path.lstat()
    return f"{stat.st_dev}:{stat.st_ino}"


def check_leases():
    with subprocess.Popen(
        [str(repo / "scripts/operation-lock"), manifest["id"]],
        env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    ) as lock:
        assert lock.stdout.readline() == "locked\n"
        current = request()
        current["expected"] = inspect(current)
        command = (repo / "scripts/prepare-target", "prepare", json.dumps(current))
        assert run(*command, good=False).returncode != 0
        ready = base / "child-ready"
        revision = run("git", "-C", root, "rev-parse", "HEAD").stdout.strip()
        with subprocess.Popen(
            [
                str(repo / "scripts/run-target"), manifest["id"], str(destination),
                str(root), stamp(destination), stamp(root), "true", revision,
                "sh", "-c", 'printf ready > "$1"; read -r line || true', "sh", str(ready),
            ],
            env=env, stdin=subprocess.PIPE,
        ) as child:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                assert child.poll() is None, "guarded child exited before acquiring its lease"
                time.sleep(0.01)
            assert ready.exists(), "guarded child did not start"
            lock.stdin.close()
            lock.wait(timeout=5)
            assert run(*command, good=False).returncode != 0, "child lost its lease"
            child.communicate(timeout=5)
            assert child.returncode == 0
    prepare(request())


try:
    local = request("local-source", dest=root)
    assert inspect(local)["operation"] == "reuse"
    prepare(local)
    assert not (home / "rescans").exists()
    link = request()
    assert inspect(link)["operation"] == "create"
    prepare(link)
    assert destination.is_symlink() and destination.resolve() == root
    assert (home / "rescans").read_text() == "rescan"
    inode = destination.lstat().st_ino
    prepare(link)
    assert destination.lstat().st_ino == inode
    assert (home / "rescans").read_text() == "rescan"

    upstream = request("git-clone", url)
    prepare(upstream)
    assert not destination.is_symlink() and (destination / ".git").is_dir()
    assert (root / "Main.qml").exists()
    assert inspect(upstream)["operation"] == "reuse"
    inode = destination.stat().st_ino
    prepare(upstream)
    assert destination.stat().st_ino == inode
    offline = base / "offline.git"
    remote.rename(offline)
    prepare(upstream)
    assert destination.stat().st_ino == inode
    offline.rename(remote)

    (destination / ".gitignore").write_text("ignored\n")
    (destination / "ignored").write_text("important")
    (destination / "extra").write_text("important")
    (destination / "Main.qml").write_text("changed\n")
    run("git", "-C", destination, "config", "user.email", "test@example.org")
    run("git", "-C", destination, "config", "user.name", "test")
    run("git", "-C", destination, "add", "extra")
    run("git", "-C", destination, "commit", "-m", "local work")
    pinned = request("git-clone", url, ref={"tag": "v1"})
    report = inspect(pinned)
    assert report["operation"] == "replace" and report["ahead"] == "1", report
    assert report["modified"] == 1 and report["ignored"] == 1, report
    assert prepare(pinned, good=False).returncode != 0
    assert (destination / "ignored").exists()
    prepare(pinned, approve=True)
    assert run("git", "-C", destination, "rev-parse", "HEAD").stdout.strip() == first
    assert (destination / ".git").is_dir() and inspect(pinned)["operation"] == "reuse"
    commit = request("git-clone", url, ref={"commit": first})
    assert inspect(commit)["operation"] == "reuse"
    prepare(commit)

    worktree = base / "worktree"
    run("git", "-C", root, "worktree", "add", "--detach", worktree)
    assert inspect(request(dest=worktree), good=False).returncode != 0
    assert inspect(request("local-source", source=str(worktree), dest=worktree))["operation"] == "reuse"
    bad = request("git-clone", url, ref={"tag": "does-not-exist"})
    inode = destination.stat().st_ino
    assert prepare(bad, approve=True, good=False).returncode != 0
    assert destination.stat().st_ino == inode
    assert inspect(request(dest=root / "cycle"), good=False).returncode != 0
    prepare(link, approve=True)
    assert destination.is_symlink() and (root / ".git").exists()
    protected = request("git-clone", url, dest=root, ref={"tag": "v1"})
    assert inspect(protected, good=False).returncode != 0

    stale = link | {"expected": inspect(link)}
    destination.unlink()
    destination.symlink_to(remote)
    assert run(repo / "scripts/prepare-target", "prepare", json.dumps(stale), good=False).returncode != 0
    assert destination.resolve() == remote
    prepare(link)
    assert destination.resolve() == root
    broken = base / "broken"
    broken.symlink_to(base / "missing")
    prepare(request(dest=broken))
    assert broken.resolve() == root
    ordinary = base / "ordinary"
    ordinary.mkdir()
    (ordinary / "keep").write_text("keep")
    assert inspect(request(dest=ordinary), good=False).returncode != 0
    assert (ordinary / "keep").exists()
    stale_config = request(dest=base / "new-link")
    stale_config["expected"] = inspect(stale_config)
    config.write_text(config.read_text() + " ")
    assert run(repo / "scripts/prepare-target", "prepare", json.dumps(stale_config), good=False).returncode != 0
    check_leases()

    env.update({
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "url." + url + ".insteadOf",
        "GIT_CONFIG_VALUE_0": "https://github.com/fixture/plugin.git",
    })
    executable("curl", "printf '{\"draft\":false,\"tag_name\":\"v1\"}\\n'\n")
    release = request("git-clone", "https://github.com/fixture/plugin.git", ref={"release": "v1"})
    prepare(release)
    assert inspect(release)["operation"] == "reuse"
    prepare(request(), approve=True)
    for key in ("GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"):
        env.pop(key)

    collision = base / "collision"
    mv = executable("mv", '''
for arg do target=$arg; done
mkdir -p "$target"
printf keep > "$target/foreign"
exec /usr/bin/mv "$@"
''')
    assert prepare(request(dest=collision), good=False).returncode != 0
    assert (collision / "foreign").read_text() == "keep"
    mv.unlink()
    native = base / "native-link"
    prepare(request(dest=native))
    assert native.is_symlink() and native.resolve() == root
    assert run("omarchy", "plugin", "validate", native, good=False).returncode != 0
    assert not list(home.rglob("previous-*"))
    print("[ok] build targets: preparation, refs, no-op reuse, safety, validation, leases")
finally:
    fixture.cleanup()
