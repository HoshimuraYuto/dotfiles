import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scan = join(repo, "scripts/scan-leaks.sh");

// Built at run time so this repository never holds a token-shaped string
const token = ["ghp", "_", "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"].join("");

function git(cwd, ...args) {
  const result = spawnSync(
    "git",
    [
      "-c",
      "commit.gpgsign=false",
      "-c",
      "core.hooksPath=/dev/null",
      "-c",
      "user.name=t",
      "-c",
      "user.email=t@example.com",
      ...args,
    ],
    { cwd, encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
}

// A clone with an upstream, this repository's secretlint and config, and one pushed commit
function fixture(t) {
  // tmpdir() is behind a symlink on macOS; the report must still show relative paths
  const root = mkdtempSync(join(tmpdir(), "dotfiles-scan-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const clone = join(root, "clone");
  git(root, "init", "-q", "--bare", "remote.git");
  git(root, "clone", "-q", "remote.git", "clone");
  symlinkSync(join(repo, "node_modules"), join(clone, "node_modules"));
  copyFileSync(
    join(repo, ".secretlintrc.json"),
    join(clone, ".secretlintrc.json"),
  );
  writeFileSync(join(clone, ".gitignore"), "node_modules\n");
  commit(clone, "README.md", "hello\n");
  git(clone, "push", "-q", "origin", "HEAD");
  return clone;
}

function commit(clone, file, text) {
  writeFileSync(join(clone, file), text);
  git(clone, "add", "-A");
  git(clone, "commit", "-q", "-m", "chore: change");
}

function run(clone) {
  return spawnSync(scan, [clone], { encoding: "utf8" });
}

test("a clean repository passes silently", (t) => {
  const result = run(fixture(t));
  assert.equal(result.status, 0, result.stdout);
  assert.equal(result.stdout, "");
});

test("a tracked file with a secret is reported without the value", (t) => {
  const clone = fixture(t);
  commit(clone, "notes.txt", `token ${token}\n`);
  const result = run(clone);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /^notes\.txt: line 1/m);
  assert.doesNotMatch(result.stdout, new RegExp(token));
});

test("a value removed again is still reported until pushed", (t) => {
  const clone = fixture(t);
  commit(clone, "notes.txt", `token ${token}\n`);
  commit(clone, "notes.txt", "");
  const removed = run(clone);
  assert.equal(removed.status, 1);
  assert.match(removed.stdout, /^unpushed-commits\.diff: line/m);
  assert.doesNotMatch(removed.stdout, /notes\.txt/);
  git(clone, "push", "-q", "origin", "HEAD");
  assert.equal(run(clone).status, 0);
});

test("personal data shapes are reported", async (t) => {
  // Joined at run time, or the pre-commit hook rejects this file
  for (const sample of [
    ["mail someone", "corp-mail.co.jp"].join("@"),
    ["path ", "Users/someone/project"].join("/"),
    ["path ", "home/someone/.ssh"].join("/"),
    ["host 192", "168.1.20"].join("."),
    ["host 10", "0.0.5"].join("."),
    ["machine box", "tail1234.ts.net"].join("."),
  ]) {
    await t.test(sample, (t) => {
      const clone = fixture(t);
      commit(clone, "notes.txt", `${sample}\n`);
      assert.equal(run(clone).status, 1);
    });
  }
});

test("placeholders and public values pass", (t) => {
  const clone = fixture(t);
  commit(
    clone,
    "notes.txt",
    [
      "path ~/dotfiles and $HOME/.config",
      "path /Users/Shared/file and /home/linuxbrew/.linuxbrew",
      "mail user@example.com and fake@mail.test",
      "commit 4d2377c5f6a0e1b2c3d4e5f60718293a4b5c6d7e",
      "pkg@1.2.3 and version 10.2",
      "",
    ].join("\n"),
  );
  const result = run(clone);
  assert.equal(result.status, 0, result.stdout);
});

test("a repository without secretlint cannot be scanned", (t) => {
  const clone = fixture(t);
  unlinkSync(join(clone, "node_modules"));
  const result = run(clone);
  assert.equal(result.status, 2);
  assert.match(result.stdout, /run npm install/);
});
