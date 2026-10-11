import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// A fake `hermes` that keeps each profile's settings as one file per key, so
// the tests never touch the real Hermes home or the network.
const stub = `#!/usr/bin/env bash
set -eu
[[ $1 == -p ]] && { p=$2; shift 2; } || p=default
root=$FAKE_HERMES
[[ $p == default ]] && home=$root || home=$root/profiles/$p
echo "$p $*" >> "$root.log"
case "$1 $2" in
  "profile create") mkdir -p "$root/profiles/$3/cfg" ;;
  "config path") [[ -d $home/cfg ]] || exit 1; echo "$home/config.yaml" ;;
  "config get") [[ -f $home/cfg/$4 ]] || { echo "Config key not set: $4" >&2; exit 1; }; cat "$home/cfg/$4" ;;
  "config set") v=$4; jq -e . <<< "$v" > /dev/null 2>&1 || v=$(jq -n --arg v "$4" '$v'); echo "$v" > "$home/cfg/$3" ;;
  "skills list-modified") cat "$home/modified" 2> /dev/null || true ;;
  "plugins install") mkdir -p "$home/plugins/$3"; printf '{\\n  "catalog_name": "%s"\\n}\\n' "$3" > "$home/plugins/$3/.hermes-catalog.json" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
`;

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "dotfiles-hermes-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, "bin");
  const hermes = join(root, "hermes");
  mkdirSync(bin);
  mkdirSync(join(hermes, "cfg"), { recursive: true });
  writeFileSync(join(bin, "hermes"), stub, { mode: 0o755 });
  // Record the npm step instead of installing anything
  writeFileSync(
    join(bin, "mise"),
    `#!/bin/sh\necho "mise $* in $PWD" >> "${root}/mise.log"\n`,
    { mode: 0o755 },
  );
  // A stand-in for the private repository with two profiles
  const private_ = join(root, "private");
  const profiles = join(private_, "hermes", "profiles");
  const write = (path, text) => {
    mkdirSync(dirname(join(profiles, path)), { recursive: true });
    writeFileSync(join(profiles, path), text);
  };
  write(
    "default/config.txt",
    '# comment\nmodel.default "m"\nagent.max_turns 500\n',
  );
  write("default/plugins.txt", "# comment\nsome-plugin\n");
  write("default/skills/devops/own-skill/SKILL.md", "x\n");
  write(
    "dotfiles/config.txt",
    'terminal.cwd "~/dotfiles"\n' +
      'skills.create_dir "~/dotfiles-private/hermes/profiles/dotfiles/skills"\n' +
      'skills.external_dirs ["~/dotfiles-private/hermes/profiles/dotfiles/skills", "~/dotfiles-private/hermes/skills"]\n' +
      'model.provider "p"\n',
  );
  write("dotfiles/plugins.txt", "some-plugin\n");
  writeFileSync(join(private_, "package.json"), "{}\n");
  const env = {
    ...process.env,
    HOME: join(root, "home"),
    DOTFILES_PRIVATE: private_,
    FAKE_HERMES: hermes,
    PATH: `${bin}:${process.env.PATH}`,
  };
  return {
    hermes,
    env,
    private_,
    miseLog: () =>
      existsSync(join(root, "mise.log"))
        ? readFileSync(join(root, "mise.log"), "utf8")
        : "",
    log: () => readFileSync(`${hermes}.log`, "utf8"),
    get: (profile, key) => {
      const home =
        profile === "default" ? hermes : join(hermes, "profiles", profile);
      return JSON.parse(readFileSync(join(home, "cfg", key), "utf8"));
    },
    run: (...args) =>
      spawnSync("bash", [join(repo, "hermes", "install.sh"), ...args], {
        cwd: repo,
        env,
        encoding: "utf8",
      }),
  };
}

function succeeded(result) {
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
}

test("dry run changes nothing", (t) => {
  const f = fixture(t);
  const result = f.run("-n");
  succeeded(result);
  assert.match(result.stdout, /would set {2}default: model.default/);
  assert.match(result.stdout, /would add {2}default: plugin some-plugin/);
  assert.match(result.stdout, /would add {2}profile dotfiles/);
  assert.match(result.stdout, /would run {2}npm install in .*private/);
  assert.equal(f.miseLog(), "");
  assert.deepEqual(readdirSync(join(f.hermes, "cfg")), []);
  assert.ok(!existsSync(join(f.hermes, "profiles")));
  assert.doesNotMatch(f.log(), / (config set|profile create|plugins install)/);
});

test("profiles, plugins and settings are applied once", (t) => {
  const f = fixture(t);
  succeeded(f.run());
  const home = join(f.hermes, "..", "home");
  assert.equal(f.get("dotfiles", "terminal.cwd"), join(home, "dotfiles"));
  assert.equal(
    f.get("dotfiles", "skills.create_dir"),
    join(home, "dotfiles-private/hermes/profiles/dotfiles/skills"),
  );
  assert.deepEqual(f.get("dotfiles", "skills.external_dirs"), [
    join(home, "dotfiles-private/hermes/profiles/dotfiles/skills"),
    join(home, "dotfiles-private/hermes/skills"),
  ]);
  assert.equal(f.get("default", "agent.max_turns"), 500);
  assert.ok(
    existsSync(join(f.hermes, "profiles/dotfiles/plugins/some-plugin")),
  );
  // Plugins come before settings so the provider exists when it is selected
  const log = f.log();
  assert.ok(
    log.indexOf("dotfiles plugins install") <
      log.indexOf("dotfiles config set model.provider"),
  );

  // Installs the private repository's git hooks
  assert.equal(f.miseLog(), `mise exec -- npm install in ${f.private_}\n`);

  const rerun = f.run();
  succeeded(rerun);
  assert.doesNotMatch(rerun.stdout, /^(?!ok ).+/m);
});

test("skills outside the repo are reported unless Hermes owns them", (t) => {
  const f = fixture(t);
  const skills = join(f.hermes, "skills");
  for (const name of ["bundled-skill", "new-skill"]) {
    mkdirSync(join(skills, "misc", name), { recursive: true });
    writeFileSync(join(skills, "misc", name, "SKILL.md"), "x\n");
  }
  writeFileSync(join(skills, ".bundled_manifest"), "bundled-skill:abc\n");
  writeFileSync(join(f.hermes, "modified"), "  ~ bundled-skill\n");
  const result = f.run("-n");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /UNMANAGED {2}default: .*misc\/new-skill$/m);
  assert.match(
    result.stdout,
    /UNMANAGED {2}default: bundled-skill \(edited bundled skill\)/,
  );
  assert.doesNotMatch(result.stdout, /misc\/bundled-skill/);
});

test("a local copy of a repo skill is reported, not replaced", (t) => {
  const f = fixture(t);
  const copy = join(f.hermes, "skills/devops/own-skill");
  mkdirSync(copy, { recursive: true });
  writeFileSync(join(copy, "SKILL.md"), "local\n");
  const result = f.run();
  assert.equal(result.status, 1);
  assert.match(result.stdout, /CONFLICT {3}default: .*own-skill/);
  assert.equal(readFileSync(join(copy, "SKILL.md"), "utf8"), "local\n");
});

test("a missing private repository stops before touching Hermes", (t) => {
  const f = fixture(t);
  const result = spawnSync("bash", [join(repo, "hermes", "install.sh"), "-n"], {
    cwd: repo,
    env: { ...f.env, DOTFILES_PRIVATE: join(f.hermes, "nowhere") },
    encoding: "utf8",
  });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /^MISSING /);
  assert.ok(!existsSync(`${f.hermes}.log`));
});
