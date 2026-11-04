declare module '@citation-js/core' {
  export class Cite {
    constructor(data: string, options?: { forceType?: string });
    data: unknown[];
  }
}
declare module '@citation-js/plugin-bibtex';
