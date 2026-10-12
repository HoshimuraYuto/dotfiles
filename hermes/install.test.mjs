import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
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
  # Plugins named bundled-* ship with the fake Hermes and only need enabling
  "plugins info")
    [[ $3 == bundled-* ]] || { echo "$3 [community]"; exit 0; }
    [[ -f $home/enabled/$3 ]] && s=enabled || s="not enabled"
    printf '%s v1\\nStatus: %s\\nSource: bundled\\n' "$3" "$s" ;;
  "plugins enable") [[ $3 == bundled-* ]] || exit 1; mkdir -p "$home/enabled"; touch "$home/enabled/$3" ;;
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
  // launchctl and notifications are recorded, never sent to the real session
  for (const command of ["launchctl", "osascript", "fswatch"]) {
    writeFileSync(
      join(bin, command),
      `#!/bin/sh\necho "${command} $*" >> "${root}/${command}.log"\n` +
        (command === "launchctl"
          ? `case $1 in bootstrap) touch "${root}/loaded" ;; print) [ -f "${root}/loaded" ] ;; esac\n`
          : ""),
      { mode: 0o755 },
    );
  }
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
      'skills.external_dirs ["~/dotfiles-private/hermes/profiles/dotfiles/skills", "~/dotfiles-private/hermes/skills", "~/.local/share/dotfiles/hermes/skills"]\n' +
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
    calls: (command) =>
      existsSync(join(root, `${command}.log`))
        ? readFileSync(join(root, `${command}.log`), "utf8")
        : "",
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

test("shared rules become one generated, always-loaded skill", (t) => {
  const f = fixture(t);
  const skill = join(
    f.env.HOME,
    ".local/share/dotfiles/hermes/skills/dotfiles-rules/SKILL.md",
  );
  const preview = f.run("-n");
  succeeded(preview);
  assert.match(preview.stdout, /would write .*dotfiles-rules\/SKILL\.md/);
  assert.ok(!existsSync(skill));

  writeFileSync(
    join(f.private_, "hermes", "instructions.md"),
    "# Hermes only\n",
  );
  succeeded(f.run());
  const text = readFileSync(skill, "utf8");
  assert.match(text, /^---\nname: dotfiles-rules\n# Generated by /);
  for (const file of readdirSync(join(repo, "rules"))) {
    const heading = readFileSync(join(repo, "rules", file), "utf8").split(
      "\n",
    )[0];
    assert.ok(text.includes(heading), heading);
  }
  assert.ok(text.trimEnd().endsWith("# Hermes only"));

  // Stale generated text is rewritten; a hand-written file is left alone
  writeFileSync(skill, text + "\nStale.\n");
  assert.match(f.run().stdout, /generated {2}.*dotfiles-rules/);
  assert.equal(readFileSync(skill, "utf8"), text);
  writeFileSync(skill, "---\nname: mine\n---\n");
  const conflict = f.run();
  assert.equal(conflict.status, 1);
  assert.match(conflict.stdout, /CONFLICT {3}.*unmanaged instructions/);
  assert.equal(readFileSync(skill, "utf8"), "---\nname: mine\n---\n");
});

test("shared settings reach every profile, including ones outside the repo", (t) => {
  const f = fixture(t);
  writeFileSync(
    join(f.private_, "hermes", "config.txt"),
    '# comment\nskills.auto_load ["dotfiles-rules"]\n' +
      'skills.external_dirs ["~/.local/share/dotfiles/hermes/skills"]\n' +
      'skills.create_dir "~/repo/{profile}/skills"\nagent.max_turns 90\n',
  );
  // A profile created on this machine (say, from the Bots tab) with no repo directory
  mkdirSync(join(f.hermes, "profiles", "bot", "cfg"), { recursive: true });
  succeeded(f.run());
  const home = join(f.hermes, "..", "home");
  for (const profile of ["default", "dotfiles", "bot"]) {
    assert.deepEqual(f.get(profile, "skills.auto_load"), ["dotfiles-rules"]);
  }
  for (const profile of ["default", "bot"]) {
    assert.equal(
      f.get(profile, "skills.create_dir"),
      join(home, "repo", profile, "skills"),
    );
  }
  // The profile's own config.txt wins over the shared one
  assert.equal(
    f.get("dotfiles", "skills.create_dir"),
    join(home, "dotfiles-private/hermes/profiles/dotfiles/skills"),
  );
  assert.equal(f.get("default", "agent.max_turns"), 500);
  assert.equal(f.get("bot", "agent.max_turns"), 90);
  // Nothing is written into the private repository for the new profile
  assert.ok(!existsSync(join(f.private_, "hermes", "profiles", "bot")));
  const rerun = f.run();
  succeeded(rerun);
  assert.doesNotMatch(rerun.stdout, /^(?!ok ).+/m);
});

// The shared always-on skill, as the private repository configures it
function sharedRules(f) {
  writeFileSync(
    join(f.private_, "hermes", "config.txt"),
    'skills.external_dirs ["~/.local/share/dotfiles/hermes/skills"]\n' +
      'skills.auto_load ["dotfiles-rules"]\n',
  );
}

test("a launch agent re-runs the installer when a profile appears", (t) => {
  const f = fixture(t);
  const plist = join(
    f.env.HOME,
    "Library/LaunchAgents/dotfiles.hermes-sync.plist",
  );
  const preview = f.run("-n");
  assert.match(preview.stdout, /would write .*dotfiles.hermes-sync.plist/);
  assert.ok(!existsSync(plist));

  succeeded(f.run());
  const text = readFileSync(plist, "utf8");
  assert.ok(text.includes(`<string>${join(repo, "hermes/watch.sh")}</string>`));
  assert.ok(text.includes(`<string>${f.hermes}</string>`));
  // launchd does not inherit the installer's HOME, so the agent must be told it
  assert.ok(text.includes(`<key>HOME</key><string>${f.env.HOME}</string>`));
  // Kept running; no polling and no launchd WatchPaths
  assert.match(text, /<key>KeepAlive<\/key><true\/>/);
  assert.doesNotMatch(text, /StartInterval|WatchPaths/);
  // Filled in from hermes/dotfiles.hermes-sync.plist, with nothing left over
  assert.doesNotMatch(text, /@[A-Z]+@/);
  assert.match(f.calls("launchctl"), /^launchctl bootstrap gui\/\d+ /m);

  writeFileSync(plist, "mine\n");
  const conflict = f.run();
  assert.equal(conflict.status, 1);
  assert.match(conflict.stdout, /CONFLICT {3}.*not generated by this script/);
  assert.equal(readFileSync(plist, "utf8"), "mine\n");
});

test("without fswatch the launch agent is reported, not written", (t) => {
  const f = fixture(t);
  // A PATH with the stubs but no fswatch
  const bin = join(f.env.HOME, "..", "bin");
  rmSync(join(bin, "fswatch"));
  const path = `${bin}:/usr/bin:/bin`;
  const result = spawnSync("bash", [join(repo, "hermes", "install.sh")], {
    cwd: repo,
    env: { ...f.env, PATH: path },
    encoding: "utf8",
  });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /^MISSING {4}fswatch/m);
  assert.ok(
    !existsSync(
      join(f.env.HOME, "Library/LaunchAgents/dotfiles.hermes-sync.plist"),
    ),
  );
});

test("an automatic run waits for a run in progress instead of giving up", async (t) => {
  const f = fixture(t);
  sharedRules(f);
  succeeded(f.run());
  const lock = join(f.env.HOME, ".local/state/dotfiles/hermes-install.lock");
  mkdirSync(lock, { recursive: true });
  // A live process holds the lock: this test itself
  writeFileSync(join(lock, "pid"), `${process.pid}\n`);
  const byHand = f.run();
  assert.equal(byHand.status, 1);
  assert.match(byHand.stdout, /^BUSY /m);

  const auto = spawn("bash", [join(repo, "hermes", "install.sh"), "--auto"], {
    cwd: repo,
    env: f.env,
  });
  const done = new Promise((ok) => auto.on("exit", ok));
  await new Promise((ok) => setTimeout(ok, 2000));
  assert.equal(auto.exitCode, null, "the automatic run must still be waiting");
  rmSync(lock, { recursive: true, force: true });
  assert.equal(await done, 0);

  // A lock left by a killed run is taken over
  mkdirSync(lock, { recursive: true });
  writeFileSync(join(lock, "pid"), "999999\n");
  succeeded(f.run());
});

test("the automatic run configures a new bot profile without asking", (t) => {
  const f = fixture(t);
  sharedRules(f);
  succeeded(f.run());
  // A bot made in the desktop app after the installer ran
  mkdirSync(join(f.hermes, "profiles", "bot", "cfg"), { recursive: true });
  const npm = f.miseLog();
  const auto = f.run("--auto");
  succeeded(auto);
  assert.match(auto.stdout, /set {8}bot: skills.auto_load/);
  assert.deepEqual(f.get("bot", "skills.auto_load"), ["dotfiles-rules"]);
  // Only settings: no npm, no new launch agent, no notification
  assert.equal(f.miseLog(), npm);
  assert.equal(f.calls("osascript"), "");
  assert.equal(f.calls("launchctl").match(/bootstrap/g).length, 1);
});

test("an automatic run for a named profile touches only that profile", (t) => {
  const f = fixture(t);
  sharedRules(f);
  succeeded(f.run());
  mkdirSync(join(f.hermes, "profiles", "bot", "cfg"), { recursive: true });
  const calls = f.log().length;
  const auto = f.run("--auto", "bot");
  succeeded(auto);
  assert.deepEqual(f.get("bot", "skills.auto_load"), ["dotfiles-rules"]);
  assert.doesNotMatch(auto.stdout, /(default|dotfiles):/);
  assert.doesNotMatch(f.log().slice(calls), /^(default|dotfiles) config/m);
});

test("a profile without its always-on skill is reported on every run", (t) => {
  const f = fixture(t);
  sharedRules(f);
  succeeded(f.run());
  // Someone drops the skill from one profile
  writeFileSync(
    join(f.hermes, "profiles", "dotfiles", "cfg", "skills.auto_load"),
    "[]\n",
  );
  // ...and the setting cannot be written back
  const broken = join(f.env.HOME, "..", "bin", "hermes");
  writeFileSync(
    broken,
    readFileSync(broken, "utf8").replace(
      '"config set")',
      '"config set") [[ $3 == skills.auto_load ]] && exit 1;',
    ),
  );
  for (let run = 0; run < 2; run++) {
    const result = f.run("--auto");
    assert.equal(result.status, 1);
    assert.match(result.stdout, /NOT LOADED dotfiles: dotfiles-rules/);
  }
  assert.equal(f.calls("osascript").match(/NOT LOADED dotfiles/g).length, 2);

  // The flag: a profile listed in skip-profiles.txt is left alone
  writeFileSync(
    join(f.private_, "hermes", "skip-profiles.txt"),
    "# not mine\ndotfiles\n",
  );
  const skipped = f.run("--auto");
  succeeded(skipped);
  assert.doesNotMatch(skipped.stdout, /dotfiles:/);
});

test("a missing always-on skill is reported even when the setting is right", (t) => {
  const f = fixture(t);
  sharedRules(f);
  succeeded(f.run());
  rmSync(join(f.env.HOME, ".local/share/dotfiles/hermes/skills"), {
    recursive: true,
  });
  // A dry run (what scripts/check.sh makes) reports it; a real run regenerates it
  const result = f.run("-n");
  assert.equal(result.status, 1);
  assert.match(
    result.stdout,
    /NOT LOADED default: dotfiles-rules is in no skill directory/,
  );
  succeeded(f.run("--auto"));
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
    join(home, ".local/share/dotfiles/hermes/skills"),
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

test("shared plugins reach every profile, bundled ones are enabled", (t) => {
  const f = fixture(t);
  writeFileSync(
    join(f.private_, "hermes", "plugins.txt"),
    "# every profile\nbundled-guard\nshared-plugin\n\nsome-plugin\n",
  );
  const dry = f.run("-n");
  succeeded(dry);
  assert.match(dry.stdout, /would enable default: plugin bundled-guard/);
  assert.doesNotMatch(f.log(), / plugins (enable|install)/);

  succeeded(f.run());
  for (const home of [f.hermes, join(f.hermes, "profiles/dotfiles")]) {
    assert.ok(existsSync(join(home, "enabled/bundled-guard")));
    assert.ok(existsSync(join(home, "plugins/shared-plugin")));
    assert.ok(!existsSync(join(home, "plugins/bundled-guard")));
  }
  // A plugin in both lists is installed once per profile
  assert.equal(
    f.log().match(/^dotfiles plugins install some-plugin/gm).length,
    1,
  );
  // Shared plugins come first, still before the settings
  const log = f.log();
  assert.ok(
    log.indexOf("dotfiles plugins enable bundled-guard") <
      log.indexOf("dotfiles plugins install some-plugin"),
  );
  assert.ok(
    log.indexOf("dotfiles plugins install some-plugin") <
      log.indexOf("dotfiles config set model.provider"),
  );

  const rerun = f.run();
  succeeded(rerun);
  assert.doesNotMatch(rerun.stdout, /^(?!ok ).+/m);
});

test("a new bot gets the shared plugins from the automatic run", (t) => {
  const f = fixture(t);
  writeFileSync(
    join(f.private_, "hermes", "plugins.txt"),
    "bundled-guard\nshared-plugin\n",
  );
  succeeded(f.run());
  // A bot made in the desktop app, with no directory in the private repo
  const bot = join(f.hermes, "profiles", "bot");
  mkdirSync(join(bot, "cfg"), { recursive: true });
  const auto = f.run("--auto", "bot");
  succeeded(auto);
  assert.match(auto.stdout, /enabled {4}bot: plugin bundled-guard/);
  assert.ok(existsSync(join(bot, "enabled/bundled-guard")));
  assert.ok(existsSync(join(bot, "plugins/shared-plugin")));
  // Only the shared list: the repo profiles' own plugins stay theirs
  assert.ok(!existsSync(join(bot, "plugins/some-plugin")));
});

test("a profile's own external skills are installed for that profile only", (t) => {
  const f = fixture(t);
  const bin = join(f.env.HOME, "..", "bin");
  // A fake skills CLI: records the call and installs into ./.agents/skills
  writeFileSync(
    join(bin, "npx"),
    `#!/usr/bin/env bash
echo "npx $* in $PWD" >> "${bin}/../npx.log"
while [[ $# -gt 0 ]]; do [[ $1 == --skill ]] && name=$2; shift; done
mkdir -p ".agents/skills/$name" && echo x > ".agents/skills/$name/SKILL.md"
`,
    { mode: 0o755 },
  );
  const list = join(f.private_, "hermes/profiles/default/external-skills.txt");
  writeFileSync(
    list,
    "# comment\nowner/repo#abc123  one-skill\nowner/repo  unpinned\n",
  );
  const skills = (p) =>
    join(
      f.env.HOME,
      ".local/share/dotfiles/hermes/profiles",
      p,
      ".agents/skills",
    );

  const dry = f.run("-n");
  assert.equal(dry.status, 1);
  assert.match(
    dry.stdout,
    /would add {2}default: skill one-skill <- owner\/repo#abc123/,
  );
  // An entry without a pinned ref is refused
  assert.match(
    dry.stdout,
    /INVALID {4}default: external skill owner\/repo unpinned/,
  );
  assert.ok(!existsSync(join(bin, "..", "npx.log")));

  writeFileSync(list, "owner/repo#abc123  one-skill\n");
  succeeded(f.run());
  assert.ok(existsSync(join(skills("default"), "one-skill/SKILL.md")));
  assert.ok(!existsSync(skills("dotfiles")));
  const npx = readFileSync(join(bin, "..", "npx.log"), "utf8");
  assert.match(npx, /skills add owner\/repo#abc123 --skill one-skill .*--yes/);
  assert.doesNotMatch(npx, / --global/);

  const rerun = f.run();
  succeeded(rerun);
  assert.match(rerun.stdout, /ok {9}default: skill one-skill/);
  assert.equal(readFileSync(join(bin, "..", "npx.log"), "utf8"), npx);
});

test("a plugin enabled outside the lists is reported", (t) => {
  const f = fixture(t);
  succeeded(f.run());
  // some-plugin is listed under its catalog name, enabled under its directory name
  const dir = join(f.hermes, "plugins", "some-plugin-dir");
  mkdirSync(dir, { recursive: true });
  writeFileSync(
    join(dir, ".hermes-catalog.json"),
    '{ "catalog_name": "some-plugin" }\n',
  );
  writeFileSync(
    join(f.hermes, "cfg", "plugins.enabled"),
    '["some-plugin-dir", "hand-made"]\n',
  );
  const result = f.run("-n");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /UNMANAGED {2}default: plugin hand-made/);
  assert.doesNotMatch(result.stdout, /plugin some-plugin(-dir)? \(/);
  // The automatic run has no one to report to
  assert.doesNotMatch(f.run("--auto").stdout, /UNMANAGED/);
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
