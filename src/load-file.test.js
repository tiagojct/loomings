import { describe, it, expect, vi, afterEach } from 'vitest';
import { adoptFileHandle, forgetFile, saveFile } from './browser.js';
import { loadFileAfterConfirmation } from './load-file.js';

function writableHandle(name) {
  const write = vi.fn();
  const close = vi.fn();
  const createWritable = vi.fn(async () => ({ write, close }));
  return {
    handle: {
      kind: 'file',
      name,
      queryPermission: async () => 'granted',
      createWritable,
    },
    createWritable,
    write,
  };
}

describe('load file confirmation lifecycle', () => {
  afterEach(() => forgetFile());

  it('keeps the previous save target when load confirmation is declined', async () => {
    const previous = writableHandle('previous.md');
    const incoming = writableHandle('incoming.md');
    const confirmDiscard = vi.fn(async () => false);
    const load = vi.fn(async () => adoptFileHandle(incoming.handle));

    adoptFileHandle(previous.handle);
    await expect(loadFileAfterConfirmation(true, confirmDiscard, load)).resolves.toBe(false);
    expect(confirmDiscard).toHaveBeenCalledWith('Open new file?');
    expect(load).not.toHaveBeenCalled();

    await saveFile('previous.md', 'still previous');
    expect(previous.createWritable).toHaveBeenCalledOnce();
    expect(previous.write).toHaveBeenCalledWith('still previous');
    expect(incoming.createWritable).not.toHaveBeenCalled();
  });

  it('adopts the incoming save target after load confirmation succeeds', async () => {
    const previous = writableHandle('previous.md');
    const incoming = writableHandle('incoming.md');
    const confirmDiscard = vi.fn(async () => true);
    const load = vi.fn(async () => adoptFileHandle(incoming.handle));

    adoptFileHandle(previous.handle);
    await expect(loadFileAfterConfirmation(true, confirmDiscard, load)).resolves.toBe(true);
    expect(load).toHaveBeenCalledOnce();

    await saveFile('incoming.md', 'incoming text');
    expect(incoming.createWritable).toHaveBeenCalledOnce();
    expect(incoming.write).toHaveBeenCalledWith('incoming text');
    expect(previous.createWritable).not.toHaveBeenCalled();
  });
});
