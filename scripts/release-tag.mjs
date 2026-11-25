import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const STABLE_RELEASE_TAG = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

export function stableReleaseVersion(refName) {
  if (typeof refName !== 'string') return null;
  const match = STABLE_RELEASE_TAG.exec(refName);
  return match ? `${match[1]}.${match[2]}.${match[3]}` : null;
}

export function assertStableRelease(refName, packageVersion) {
  const tagVersion = stableReleaseVersion(refName);
  if (tagVersion === null) {
    throw new Error(`Release tag "${refName}" must match vMAJOR.MINOR.PATCH without a prerelease suffix.`);
  }
  if (tagVersion !== packageVersion) {
    throw new Error(`Release tag version ${tagVersion} does not match package.json version ${packageVersion}.`);
  }
}

function runCli() {
  try {
    const packageJson = JSON.parse(
      readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
    );
    assertStableRelease(process.argv[2], packageJson.version);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}

if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  runCli();
}
