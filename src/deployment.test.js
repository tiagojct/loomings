import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = fileURLToPath(new URL('..', import.meta.url));
const ci = readFileSync(join(root, '.github', 'workflows', 'ci.yml'), 'utf8');
const dockerPublish = readFileSync(
  join(root, '.github', 'workflows', 'docker-publish.yml'),
  'utf8',
);
const dockerfile = readFileSync(join(root, 'Dockerfile'), 'utf8');
const compose = readFileSync(join(root, 'docker-compose.yml'), 'utf8');

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

describe('built artifact and Docker deployment policy', () => {
  it('installs, typechecks, builds, then tests in both Node CI jobs', () => {
    const ciJob = extractJob(ci, 'test-and-build');
    const dockerJob = extractJob(dockerPublish, 'build-check');

    for (const [name, job] of [['CI', ciJob], ['Docker publish', dockerJob]]) {
      const steps = [
        'run: npm ci',
        'run: npm run typecheck',
        'run: npm run build',
        'run: npm test',
      ];
      const indexes = steps.map((step) => job.indexOf(step));
      for (const [index, step] of steps.entries()) {
        expect(indexes[index], `${name} ${step}`).toBeGreaterThanOrEqual(0);
        if (index > 0) {
          expect(indexes[index], `${name} ${step} order`).toBeGreaterThan(indexes[index - 1]);
        }
      }
    }
  });

  it('health-checks the editor app in Dockerfile and Compose', () => {
    expect(dockerfile).toMatch(/http:\/\/127\.0\.0\.1:80\/app\//);
    expect(compose).toMatch(/http:\/\/127\.0\.0\.1:80\/app\//);
  });

  it('smoke-tests the built Docker image and its security headers', () => {
    const smokeJob = extractJob(ci, 'docker-smoke');
    expect(smokeJob).toBeTruthy();
    expect(smokeJob).toContain('docker build');
    expect(smokeJob).toContain('--publish 127.0.0.1:8081:80');
    for (const path of ['/', '/app/', '/app/sw.js', '/app/manifest.webmanifest']) {
      expect(smokeJob, `smoke probe for ${path}`).toContain(`http://127.0.0.1:8081${path}`);
    }
    expect(smokeJob).toMatch(/Content-Security-Policy/i);
    expect(smokeJob).toMatch(/X-Content-Type-Options/i);
    expect(smokeJob).toMatch(/Referrer-Policy/i);
    expect(smokeJob).toMatch(/always\(\)/);
  });
});
