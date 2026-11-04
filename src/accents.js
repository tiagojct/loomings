// Comparison text with no accents, for find, completion and the filter of the
// library. "ciencia" finds "ciência", and "saúde" finds "saude".

/** @param {string} text @returns {string} */
export const withoutAccents = (text) => text.normalize('NFD').replace(/\p{Mn}/gu, '');

/** @param {string} text @returns {string} */
export const foldText = (text) => withoutAccents(text).toLowerCase();
