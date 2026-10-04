import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "dotfiles-install-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const claude = join(root, "claude");
  const codex = join(root, "codex");
  const skills = join(root, ".agents", "skills");
  // Prevent an unexpected installer regression from downloading into the real home.
  const bin = join(root, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "npx"), "#!/bin/sh\nexit 42\n", { mode: 0o755 });
  const env = {
    ...process.env,
    CLAUDE_CONFIG_DIR: claude,
    DOTFILES_CODEX_DIR: codex,
    DOTFILES_SKILLS_DIR: skills,
    PATH: `${bin}:${process.env.PATH}`,
  };
  return {
    root,
    claude,
    codex,
    skills,
    run(agent, ...args) {
      return spawnSync("bash", [join(repo, agent, "install.sh"), ...args], {
        cwd: repo,
        env,
        encoding: "utf8",
      });
    },
    seed() {
      for (const dir of [join(claude, "skills"), skills]) {
        mkdirSync(join(dir, "security-audit"), { recursive: true });
        writeFileSync(
          join(dir, "security-audit", "SKILL.md"),
          "---\nname: security-audit\ndescription: Test fixture.\n---\n",
        );
      }
    },
  };
}

function succeeded(result) {
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
}

test("dry runs preview both agents without writing destinations", (t) => {
  const f = fixture(t);
  for (const agent of ["claude", "codex"]) {
    const result = f.run(agent, "-n");
    succeeded(result);
    assert.match(result.stdout, /would link/);
    assert.match(result.stdout, /would add/);
  }
  assert.deepEqual(readdirSync(f.root), ["bin"]);
});

test("shared skills and rule link chains resolve, and installs are idempotent", (t) => {
  const f = fixture(t);
  f.seed();
  mkdirSync(join(f.codex, "rules"), { recursive: true });
  writeFileSync(join(f.codex, "config.toml"), "# unrelated local config\n");
  writeFileSync(join(f.codex, "rules", "default.rules"), "# local approvals\n");
  writeFileSync(join(f.codex, "AGENTS.md"), "");

  succeeded(f.run("claude"));
  succeeded(f.run("codex"));
  const shared = realpathSync(join(repo, "skills", "context7", "SKILL.md"));
  assert.equal(
    realpathSync(join(f.claude, "skills", "context7", "SKILL.md")),
    shared,
  );
  assert.equal(realpathSync(join(f.skills, "context7", "SKILL.md")), shared);
  assert.equal(
    realpathSync(join(f.claude, "rules", "dotfiles", "commits.md")),
    realpathSync(join(repo, "rules", "commits.md")),
  );
  assert.equal(
    readlinkSync(join(f.codex, "dotfiles.config.toml")),
    join(repo, "codex", "dotfiles.config.toml"),
  );
  const instructions = readFileSync(join(f.codex, "AGENTS.md"), "utf8");
  for (const heading of [
    "# Commits",
    "# Writing",
    "# Unknown terms",
    "# Web research",
  ]) {
    assert.ok(instructions.includes(heading));
  }
  assert.match(
    readFileSync(
      join(f.skills, "security-audit", "agents", "openai.yaml"),
      "utf8",
    ),
    /allow_implicit_invocation: false/,
  );
  for (const agent of ["claude", "codex"]) {
    const result = f.run(agent);
    succeeded(result);
    assert.doesNotMatch(result.stdout, /linked|generated|added/);
  }
  assert.equal(readFileSync(join(f.codex, "AGENTS.md"), "utf8"), instructions);
  assert.equal(
    readFileSync(join(f.codex, "config.toml"), "utf8"),
    "# unrelated local config\n",
  );
  assert.equal(
    readFileSync(join(f.codex, "rules", "default.rules"), "utf8"),
    "# local approvals\n",
  );

  writeFileSync(
    join(f.codex, "AGENTS.md"),
    instructions + "\nStale generated text.\n",
  );
  succeeded(f.run("codex"));
  assert.equal(readFileSync(join(f.codex, "AGENTS.md"), "utf8"), instructions);
});

test("unmanaged instructions, config and policy metadata are preserved", (t) => {
  const f = fixture(t);
  f.seed();
  mkdirSync(f.codex, { recursive: true });
  writeFileSync(join(f.codex, "AGENTS.md"), "My working agreements.\n");
  writeFileSync(join(f.codex, "dotfiles.config.toml"), "# mine\n");
  const policy = join(f.skills, "security-audit", "agents", "openai.yaml");
  mkdirSync(dirname(policy));
  writeFileSync(policy, "interface:\n  display_name: Custom\n");
  const result = f.run("codex");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /unmanaged instructions/);
  assert.equal(
    readFileSync(join(f.codex, "AGENTS.md"), "utf8"),
    "My working agreements.\n",
  );
  assert.equal(
    readFileSync(join(f.codex, "dotfiles.config.toml"), "utf8"),
    "# mine\n",
  );
  assert.equal(
    readFileSync(policy, "utf8"),
    "interface:\n  display_name: Custom\n",
  );
});

test("different and dangling symlinks are reported without replacement", (t) => {
  const f = fixture(t);
  f.seed();
  symlinkSync("/nonexistent/skill", join(f.skills, "context7"));
  mkdirSync(join(f.claude, "rules"));
  symlinkSync("/nonexistent/rules", join(f.claude, "rules", "dotfiles"));
  for (const agent of ["claude", "codex"]) {
    const result = f.run(agent);
    assert.equal(result.status, 1);
    assert.match(result.stdout, /CONFLICT/);
  }
  assert.equal(readlinkSync(join(f.skills, "context7")), "/nonexistent/skill");
  assert.equal(
    readlinkSync(join(f.claude, "rules", "dotfiles")),
    "/nonexistent/rules",
  );
});

test("invalid external destinations cannot create policy-only skills", (t) => {
  const f = fixture(t);
  mkdirSync(f.skills, { recursive: true });
  writeFileSync(join(f.skills, "security-audit"), "unrelated file\n");
  const result = f.run("codex");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /FAILED/);
  assert.equal(
    readFileSync(join(f.skills, "security-audit"), "utf8"),
    "unrelated file\n",
  );
});

test("external download failures are propagated without using the real home", (t) => {
  const f = fixture(t);
  const result = spawnSync(
    "bash",
    [
      "-c",
      'set -euo pipefail; repo=$1; dest=$2; skills_dest=$3; dry=false; source "$repo/scripts/install-agent.sh"; install_skills codex "$repo/codex/skills" "$4"; exit "$failed"',
      "test-install",
      repo,
      f.codex,
      f.skills,
      join(f.root, "empty-global-skills"),
    ],
    {
      env: {
        ...process.env,
        PATH: `${join(f.root, "bin")}:${process.env.PATH}`,
      },
      encoding: "utf8",
    },
  );
  assert.equal(result.status, 1);
  assert.match(result.stdout, /FAILED/);
  assert.equal(existsSync(join(f.skills, "security-audit")), false);
});

test("skills CLI discovers context7 through the Codex symlink chain", (t) => {
  const f = fixture(t);
  f.seed();
  succeeded(f.run("codex"));
  const result = spawnSync(
    process.execPath,
    [
      join(repo, "node_modules", "skills", "bin", "cli.mjs"),
      "list",
      "--agent",
      "codex",
    ],
    { cwd: f.root, encoding: "utf8" },
  );
  succeeded(result);
  assert.match(result.stdout, /context7/);
  assert.doesNotMatch(
    result.stdout + result.stderr,
    /missing required frontmatter/,
  );
  assert.ok(lstatSync(join(repo, "codex", "skills")).isSymbolicLink());
});

test("Codex parses command rules and distinguishes banned and normal commands", (t) => {
  if (spawnSync("codex", ["--version"]).status !== 0) {
    t.skip("Codex CLI is not installed");
    return;
  }
  const cases = [
    [["git", "reset", "--hard", "HEAD"], "forbidden"],
    [["git", "push", "--force", "origin", "main"], "forbidden"],
    [["rm", "-r", "-f", "fixture"], "forbidden"],
    [["python3", "-c", "pass"], "forbidden"],
    [["curl", "https://example.com"], "forbidden"],
    [["sudo", "true"], "forbidden"],
    [["git", "status"], undefined],
    [["git", "push", "origin", "main"], undefined],
    [["npm", "install"], undefined],
    // Documented prefix limitation; global instructions also forbid this form.
    [["git", "push", "origin", "main", "--force"], undefined],
  ];
  for (const [command, decision] of cases) {
    const result = spawnSync(
      "codex",
      [
        "execpolicy",
        "check",
        "--rules",
        join(repo, "codex", "rules", "dotfiles.rules"),
        "--",
        ...command,
      ],
      { encoding: "utf8" },
    );
    succeeded(result);
    assert.equal(
      JSON.parse(result.stdout).decision,
      decision,
      command.join(" "),
    );
  }
});

test("Codex accepts the profile as a trusted project config", (t) => {
  if (spawnSync("codex", ["--version"]).status !== 0) {
    t.skip("Codex CLI is not installed");
    return;
  }
  const f = fixture(t);
  mkdirSync(join(f.root, ".codex"));
  writeFileSync(
    join(f.root, ".codex", "config.toml"),
    readFileSync(join(repo, "codex", "dotfiles.config.toml")),
  );
  const result = spawnSync(
    "codex",
    [
      "-C",
      f.root,
      "-c",
      `projects.${JSON.stringify(f.root)}.trust_level="trusted"`,
      "features",
      "list",
    ],
    { encoding: "utf8" },
  );
  succeeded(result);
  assert.doesNotMatch(
    result.stderr,
    /unknown config|invalid config|unrecognized/i,
  );
});
