import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('..', import.meta.url));
const workflowsDir = join(root, '.github', 'workflows');
const workflowFiles = readdirSync(workflowsDir)
  .filter((name) => name.endsWith('.yml') || name.endsWith('.yaml'))
  .sort();

const workflows = Object.fromEntries(
  workflowFiles.map((name) => [name, readFileSync(join(workflowsDir, name), 'utf8')]),
);

const PINNED_ACTIONS = {
  'actions/checkout': '11d5960a326750d5838078e36cf38b85af677262',
  'actions/setup-node': '49933ea5288caeca8642d1e84afbd3f7d6820020',
  'actions/upload-artifact': 'ea165f8d65b6e75b540449e92b4886f43607fa02',
  'actions/download-artifact': 'd3f86a106a0bac45b974a628896c90dbdf5c8093',
  'docker/setup-qemu-action': 'c7c53464625b32c7a7e944ae62b3e17d2b600130',
  'docker/setup-buildx-action': '8d2750c68a42422c14e847fe6c8ac0403b4cbd6f',
  'docker/login-action': 'c94ce9fb468520275223c153574b00df6fe4bcc9',
  'docker/metadata-action': 'c299e40c65443455700f0fdfc63efafe5b349051',
  'docker/build-push-action': '10e90e3645eae34f1e60eeb005ba3a3d33f178e8',
};

/**
 * Extracts a job section from a workflow YAML string.
 * @param {string} yaml
 * @param {string} jobId
 * @returns {string}
 */
function extractJob(yaml, jobId) {
  const jobsIndex = yaml.indexOf('\njobs:\n');
  if (jobsIndex === -1) return '';
  const jobsBody = yaml.slice(jobsIndex + '\njobs:\n'.length);
  const jobHeaderRe = new RegExp(`^  ${jobId}:\\n`, 'm');
  const match = jobHeaderRe.exec(jobsBody);
  if (!match) return '';
  const start = match.index;
  const rest = jobsBody.slice(start + match[0].length);
  const nextJobMatch = /^  [a-zA-Z0-9_-]+:\n/m.exec(rest);
  const end = nextJobMatch ? start + match[0].length + nextJobMatch.index : jobsBody.length;
  return jobsBody.slice(start, end);
}

describe('CI workflow security policy', () => {
  it('sets top-level permissions to contents: read in every workflow', () => {
    expect(workflowFiles.length).toBeGreaterThan(0);
    for (const [name, content] of Object.entries(workflows)) {
      const beforeJobs = content.split('\njobs:\n')[0];
      expect(beforeJobs, `${name} top-level permissions`).toMatch(
        /^permissions:\n  contents: read$/m,
      );
      expect(beforeJobs, `${name} must not grant top-level write`).not.toMatch(/:\s*write\b/);
    }
  });

  it('pins every uses: reference to the approved 40-character commit SHA with a version comment', () => {
    for (const [name, content] of Object.entries(workflows)) {
      const usesLines = [...content.matchAll(/^\s*(?:-\s*)?uses:\s*(.+)$/gm)];
      expect(usesLines.length, `${name} should have uses: entries`).toBeGreaterThan(0);
      for (const [, rawTarget] of usesLines) {
        const match = /^([a-z0-9-]+\/[a-z0-9-]+)@([0-9a-f]{40})\s+#\s*v\d+/i.exec(
          rawTarget.trim(),
        );
        expect(match, `${name} unpinned uses: ${rawTarget}`).not.toBeNull();
        const [, action, sha] = /** @type {RegExpExecArray} */ (match);
        expect(sha, `${name} SHA for ${action}`).toBe(PINNED_ACTIONS[action]);
      }
    }
  });

  it('keeps the native test-and-build job read-only and uploads the release artifact on tags', () => {
    const macos = workflows['macos.yml'];
    const testJob = extractJob(macos, 'test-and-build');
    expect(testJob).toBeTruthy();
    expect(testJob).not.toMatch(/contents:\s*write/);
    expect(testJob).not.toMatch(/\bgh release\b/);
    expect(testJob).toContain('uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
    expect(testJob).toContain('name: Loomings-mac-arm64');
    expect(testJob).toContain('path: Loomings-mac-arm64.zip');
    expect(testJob).toContain('if-no-files-found: error');
  });

  it('isolates native release publication in a publish job with environment: release and contents: write', () => {
    const macos = workflows['macos.yml'];
    const publishJob = extractJob(macos, 'publish');
    expect(publishJob).toBeTruthy();
    expect(publishJob).toMatch(/^\s+needs:\s*test-and-build$/m);
    expect(publishJob).toMatch(/^\s+if:\s*startsWith\(github\.ref,\s*'refs\/tags\/v'\)$/m);
    expect(publishJob).toMatch(/^\s+environment:\s*release$/m);
    expect(publishJob).toMatch(/^\s+permissions:\n\s+contents:\s*write$/m);
    expect(publishJob).toContain(
      'uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093',
    );
    expect(publishJob).toContain('name: Loomings-mac-arm64');
    expect(publishJob).toContain('gh release');
  });
});
