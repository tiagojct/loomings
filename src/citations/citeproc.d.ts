// Types for citeproc. jsconfig.json maps the module here, so tsc does not read
// the package source.
declare const CSL: {
  Engine: new (sys: any, style: string, lang?: string, forceLang?: boolean) => any;
};
export default CSL;
