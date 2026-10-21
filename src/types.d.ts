// Ambient declarations for browser APIs TypeScript's DOM lib does not ship.
// Everything here is feature-detected at runtime (hasFileSystemAccess in
// browser.js), so the declarations promise what the guard already checks.

interface Window {
  showOpenFilePicker(options?: {
    types?: { description?: string; accept: Record<string, string[]> }[];
    multiple?: boolean;
  }): Promise<FileSystemFileHandle[]>;
  showSaveFilePicker(options?: {
    types?: { description?: string; accept: Record<string, string[]> }[];
    suggestedName?: string;
  }): Promise<FileSystemFileHandle>;
  /** Chromium only: files handed to the installed app by the OS. */
  launchQueue?: {
    setConsumer(callback: (params: { files?: FileSystemFileHandle[] }) => void): void;
  };
}

interface FileSystemFileHandle {
  queryPermission(descriptor?: { mode?: 'read' | 'readwrite' }): Promise<PermissionState>;
  requestPermission(descriptor?: { mode?: 'read' | 'readwrite' }): Promise<PermissionState>;
}

interface DataTransferItem {
  getAsFileSystemHandle?(): Promise<FileSystemFileHandle | null>;
}
