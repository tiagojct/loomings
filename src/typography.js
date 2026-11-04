import { EditorView } from '@codemirror/view';

// The character before a quote that opens it. At the document start it is a space.
const OPENS = /[\s([{]/;

/**
 * Curly quotes, em dashes and ellipses as the writer types. It rests during a
 * composition: a dead key on some layouts types ' or " on its way to an
 * accented letter, and an edit at that moment would break the letter.
 *
 * @param {() => boolean} isOn
 */
export function smartTypography(isOn) {
  return EditorView.inputHandler.of((view, from, to, text) => {
    if (!isOn() || view.composing || view.compositionStarted) return false;
    if (text === '"') {
      const prev = from > 0 ? view.state.sliceDoc(from - 1, from) : ' ';
      const rep = OPENS.test(prev) ? '“' : '”';
      view.dispatch({ changes: { from, to, insert: rep }, selection: { anchor: from + 1 } });
      return true;
    }
    if (text === "'") {
      const prev = from > 0 ? view.state.sliceDoc(from - 1, from) : ' ';
      const rep = OPENS.test(prev) ? '‘' : '’';
      view.dispatch({ changes: { from, to, insert: rep }, selection: { anchor: from + 1 } });
      return true;
    }
    if (text === '-' && from > 0 && view.state.sliceDoc(from - 1, from) === '-') {
      view.dispatch({ changes: { from: from - 1, to, insert: '—' }, selection: { anchor: from } });
      return true;
    }
    if (text === '.' && from >= 2 && view.state.sliceDoc(from - 2, from) === '..') {
      view.dispatch({ changes: { from: from - 2, to, insert: '…' }, selection: { anchor: from - 1 } });
      return true;
    }
    return false;
  });
}
