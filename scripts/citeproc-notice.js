// The notice at the top of each bundle that holds citeproc. The build puts
// citeproc and MIT code in one file, so the file must say which is which.

/** @param {string} licenceFile  the licence file, as a reader finds it from the bundle */
export const citeprocNotice = (licenceFile) =>
  `/*! This file includes citeproc-js, Copyright (c) 2009-2019 Frank Bennett, under the Common Public Attribution License Version 1.0 (CPAL-1.0). See ${licenceFile}. The other code in this file has the MIT licence, except where a file says otherwise. */`;
