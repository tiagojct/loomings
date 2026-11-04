// ========================================
// Loomings — fetch stub
// @citation-js/core imports sync-fetch-undici. The app has no network path,
// so the build aliases that package to this file. Any call throws.
// ========================================

/**
 * @returns {never}
 */
export default function syncFetch() {
  throw new Error('Network access is not available.');
}
