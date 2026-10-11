import { CodeView, parsePatchFiles } from '@pierre/diffs';
import { WorkerPoolManager } from '@pierre/diffs/worker';
import { bundledLanguages } from './shiki-local.js';

const post = message => window.webkit.messageHandlers.prDiff.postMessage(message);
const logError = console.error.bind(console);
console.error = (...errors) => {
  logError(...errors);
  post({ kind: 'error', message: errors.map(error => error?.message ?? String(error)).join(' ') });
};
const root = document.getElementById('diffs');
const workerURL = URL.createObjectURL(new Blob([__DIFF_WORKER_SOURCE__], { type: 'text/javascript' }));
const pool = new WorkerPoolManager({
  workerFactory: () => new Worker(workerURL), poolSize: 1, totalASTLRUCacheSize: 8,
  onWorkerError: event => { event.preventDefault(); post({ kind: 'error', message: 'Diff highlighting failed. Refresh files to retry.' }); },
}, {
  preferredHighlighter: 'shiki-js', theme: { light: 'pierre-light', dark: 'pierre-dark' },
  lineDiffType: 'word', maxLineDiffLength: 1_000, tokenizeMaxLineLength: 1_000,
});
const files = new Map(), patches = new Map(), items = new Map(), failedPatches = new Set();
const threadsByPath = new Map(), threadHeights = new Map();
let threadVersion = 0, pendingThread;
let threadResizeAnchor, threadResizeFrame, interactionRevision = 0;
let options = { style: 'unified', wraps: false, dark: false }, selectedPath, navigationRevision, hoveredLine, chromeFrame, lastChrome, itemVersion = 0;
const extensions = { js: 'javascript', mjs: 'javascript', cjs: 'javascript', ts: 'typescript', kt: 'kotlin', kts: 'kotlin', md: 'markdown', sh: 'shellscript', yml: 'yaml' };

function viewOptions() {
  return {
    diffStyle: options.style, overflow: options.wraps ? 'wrap' : 'scroll',
    themeType: options.dark ? 'dark' : 'light', preferredHighlighter: 'shiki-js',
    theme: { light: 'pierre-light', dark: 'pierre-dark' },
    stickyHeaders: false, disableErrorHandling: true,
    layout: { paddingTop: 8, paddingBottom: 12, gap: 12 },
    itemMetrics: { diffHeaderHeight: 44, lineHeight: 20, paddingTop: 0, paddingBottom: 0 },
    unsafeCSS: ':host{background:transparent}[data-diffs-header]{background:transparent;border:0;padding:0;height:44px;min-height:44px}:host([data-native-empty-file]) [data-line],:host([data-native-empty-file]) [data-column-number]{display:none}:host([data-native-empty-file]) [data-code]{padding:0;overflow:hidden}',
    renderCustomHeader(_file, context) {
      context.element?.toggleAttribute('data-native-empty-file', context.type === 'file');
      const header = document.createElement('div');
      header.dataset.nativeHeader = context.item.id;
      header.style.cssText = 'height:44px;width:100%;pointer-events:none';
      header.setAttribute('aria-hidden', 'true');
      return header;
    },
    renderAnnotation(annotation) {
      const body = document.createElement('div');
      if (annotation.metadata.threadID) {
        body.dataset.nativeThread = annotation.metadata.threadID;
        body.dataset.path = annotation.metadata.path;
        body.dataset.fileLevel = String(annotation.lineNumber === 0);
        body.style.cssText = `height:${threadHeights.get(annotation.metadata.threadID) ?? 180}px;width:100%;pointer-events:none`;
      } else {
        body.dataset.nativeEmptyBody = annotation.metadata.path;
        body.style.cssText = 'height:36px;width:100%;pointer-events:none';
      }
      body.setAttribute('aria-hidden', 'true');
      return body;
    },
    onPostRender: scheduleChrome,
    onLineEnter(props, context) { hoveredLine = { ...props, path: context.item.id }; scheduleChrome(); },
    enableLineSelection: true, hunkSeparators: 'line-info',
    onSelectedLinesChange(selection) {
      if (!selection) { post({ kind: 'clear-selection' }); return; }
      post({ kind: 'selection', path: selection.id, ...selection.range });
    },
  };
}
// Empty header slots reserve geometry; SwiftUI supplies all visible controls.
function scheduleChrome() {
  if (chromeFrame) return;
  chromeFrame = requestAnimationFrame(() => { chromeFrame = undefined; syncChrome(); });
}
function syncChrome() {
  const bounds = root.getBoundingClientRect();
  const headers = Array.from(root.querySelectorAll('[data-native-header]')).flatMap(header => {
    const rect = header.getBoundingClientRect();
    const body = header.closest('diffs-container')?.querySelector('[data-native-empty-body]')?.getBoundingClientRect();
    const bottom = body && body.height > 0 ? Math.max(rect.bottom, body.bottom) : rect.bottom;
    return bottom > bounds.top && rect.top < bounds.bottom
      ? [{ path: header.dataset.nativeHeader, x: rect.left, y: rect.top, width: rect.width, height: bottom - rect.top }] : [];
  });
  const visiblePath = view.getRenderedItems().find(entry => {
    const rect = entry.element.getBoundingClientRect();
    return rect.bottom > bounds.top + 1 && rect.top < bounds.bottom;
  })?.id;
  let comment = null;
  if (hoveredLine?.lineElement.isConnected) {
    const line = hoveredLine.lineElement.getBoundingClientRect(), number = hoveredLine.numberElement.getBoundingClientRect();
    if (line.top >= bounds.top && line.bottom <= bounds.bottom) comment = {
      path: hoveredLine.path, line: hoveredLine.lineNumber, side: hoveredLine.annotationSide === 'deletions' ? 'LEFT' : 'RIGHT',
      x: number.right - 12, y: line.top + (line.height - 24) / 2, width: 24, height: 24,
    };
  }
  const threads = Array.from(root.querySelectorAll('[data-native-thread]')).flatMap(element => {
    const rect = element.getBoundingClientRect();
    return rect.height > 0 && rect.bottom > bounds.top && rect.top < bounds.bottom
      ? [{ id: element.dataset.nativeThread, path: element.dataset.path, fileLevel: element.dataset.fileLevel === 'true', x: rect.left, y: rect.top, width: rect.width, height: rect.height }] : [];
  });
  const message = { kind: 'chrome', headers, threads, comment, visiblePath }, key = JSON.stringify(message);
  if (key !== lastChrome) { lastChrome = key; post(message); }
}
const view = new CodeView(viewOptions(), pool);
view.setup(root);
pool.initialize().then(() => view.render(true)).catch(error => post({ kind: 'error', message: error.message || 'Diff highlighting could not start. Refresh files to retry.' }));

function itemFor(file, patch) {
  if (!patch?.patch) return null;
  const oldPath = file.changeType === 'ADDED' ? '/dev/null' : 'a/file';
  const newPath = file.changeType === 'DELETED' ? '/dev/null' : 'b/file';
  const parsed = parsePatchFiles(`diff --git a/file b/file\n--- ${oldPath}\n+++ ${newPath}\n${patch.patch}\n`, patch.sha + ':' + file.path, true);
  if (parsed.length !== 1 || parsed[0].files.length !== 1) throw new Error('Unexpected patch structure');
  const diff = parsed[0].files[0]; diff.name = file.path; diff.prevName = patch.previous_filename;
  const ext = file.path.split('.').pop().toLowerCase(), lang = extensions[ext] ?? ext;
  diff.lang = Object.hasOwn(bundledLanguages, lang) ? lang : 'text';
  return { type: 'diff', id: file.path, fileDiff: diff, version: ++itemVersion };
}

window.prDiff = {
  setThreads(threads) {
    threadsByPath.clear(); threadVersion++;
    for (const thread of threads) {
      const group = threadsByPath.get(thread.path) ?? [];
      group.push(thread); threadsByPath.set(thread.path, group);
    }
  },
  setThreadHeight(id, height) {
    if (!Number.isFinite(height) || height <= 0 || height > 100_000 || threadHeights.get(id) === height) return;
    const bounds = root.getBoundingClientRect();
    if (!threadResizeAnchor) {
      const element = Array.from(root.querySelectorAll('[data-native-thread]')).find(element => {
        const rect = element.getBoundingClientRect();
        return rect.bottom > bounds.top && rect.top < bounds.bottom;
      });
      if (element) threadResizeAnchor = { id: element.dataset.nativeThread, top: element.getBoundingClientRect().top, interaction: interactionRevision };
    }
    threadHeights.set(id, height);
    for (const element of root.querySelectorAll('[data-native-thread]')) if (element.dataset.nativeThread === id) element.style.height = `${height}px`;
    if (!threadResizeFrame) threadResizeFrame = requestAnimationFrame(() => {
      threadResizeFrame = requestAnimationFrame(() => {
        const anchor = threadResizeAnchor;
        threadResizeAnchor = undefined; threadResizeFrame = undefined;
        const element = anchor && Array.from(root.querySelectorAll('[data-native-thread]')).find(element => element.dataset.nativeThread === anchor.id);
        if (element && anchor.interaction === interactionRevision) {
          root.scrollTop += element.getBoundingClientRect().top - anchor.top;
          view.render(true);
        }
        syncChrome();
      });
    });
    scheduleChrome();
  },
  clearHover() { hoveredLine = undefined; scheduleChrome(); },
  setFiles(nextFiles, nextPatches, reset = true) {
    if (reset) { files.clear(); patches.clear(); items.clear(); failedPatches.clear(); }
    for (const file of nextFiles) files.set(file.path, file);
    for (const patch of nextPatches) {
      if (patches.get(patch.filename)?.patch !== patch.patch) { items.delete(patch.filename); failedPatches.delete(patch.filename); }
      patches.set(patch.filename, patch);
    }
  },
  configure(paths, state, nextOptions) {
    const changedOptions = options.style !== nextOptions.style || options.wraps !== nextOptions.wraps || options.dark !== nextOptions.dark;
    options = nextOptions;
    const nextSelectedPath = paths.includes(state.selectedPath) ? state.selectedPath : undefined;
    const changedSelection = selectedPath !== nextSelectedPath || navigationRevision !== state.navigationRevision;
    navigationRevision = state.navigationRevision;
    selectedPath = nextSelectedPath;
    if (changedSelection) pendingThread = state.threadID ? { id: state.threadID, path: state.selectedPath } : undefined;
    hoveredLine = undefined;
    if (changedOptions) view.setOptions(viewOptions());
    document.documentElement.dataset.theme = options.dark ? 'dark' : 'light';
    const collapsed = new Set(state.collapsed);
    view.setItems(paths.filter(path => files.has(path)).map(path => {
      let entry = items.get(path);
      if (!entry && !collapsed.has(path) && !failedPatches.has(path)) {
        try {
          const item = itemFor(files.get(path), patches.get(path));
          if (item) { entry = { item, patch: patches.get(path)?.patch }; items.set(path, entry); }
        } catch (error) {
          failedPatches.add(path);
          post({ kind: 'file-error', path, message: error.message || 'This patch could not be rendered. Open it on GitHub.' });
        }
      }
      if (entry?.item.type === 'diff') {
        if (entry.item.collapsed !== collapsed.has(path)) entry.item = { ...entry.item, collapsed: collapsed.has(path), version: ++itemVersion };
        if (entry.threadVersion !== threadVersion) {
          const annotations = (threadsByPath.get(path) ?? []).map(thread => {
            const side = thread.side, prefix = side === 'deletions' ? 'deletion' : 'addition';
            const inPatch = entry.item.fileDiff.hunks.some(hunk => thread.line >= hunk[prefix + 'Start'] && thread.line < hunk[prefix + 'Start'] + hunk[prefix + 'Count']);
            return { side, lineNumber: inPatch ? thread.line : 0, metadata: { threadID: thread.id, path } };
          });
          entry.item = { ...entry.item, annotations, version: ++itemVersion }; entry.threadVersion = threadVersion;
        }
        return entry.item;
      }
      const headerOnly = collapsed.has(path) || !patches.has(path) || failedPatches.has(path);
      if (!entry) {
        entry = { item: { type: 'file', id: path, file: { name: path, contents: '' } } };
        items.set(path, entry);
      }
      if (entry.item.collapsed !== headerOnly || entry.threadVersion !== threadVersion) {
        entry.item = { ...entry.item, collapsed: headerOnly,
          annotations: headerOnly ? [] : [{ lineNumber: 0, metadata: { path } }, ...(threadsByPath.get(path) ?? []).map(thread => ({ lineNumber: 0, metadata: { threadID: thread.id, path } }))], version: ++itemVersion };
        entry.threadVersion = threadVersion;
      }
      return entry.item;
    }));
    view.render(true);
    if (pendingThread) {
      const entry = items.get(pendingThread.path)?.item;
      const annotation = entry?.annotations?.find(annotation => annotation.metadata.threadID === pendingThread.id);
      if (annotation && !entry.collapsed) {
        view.scrollTo(annotation.lineNumber > 0
          ? { type: 'line', id: entry.id, lineNumber: annotation.lineNumber, side: annotation.side, align: 'start', behavior: 'instant' }
          : { type: 'item', id: entry.id, align: 'start', behavior: 'instant' });
        view.render(true);
        const slot = Array.from(root.querySelectorAll('[data-native-thread]')).find(element => element.dataset.nativeThread === pendingThread.id);
        if (slot) { root.scrollTop += slot.getBoundingClientRect().top - root.getBoundingClientRect().top - 12; view.render(true); pendingThread = undefined; }
      }
    } else if (changedSelection && state.focus && selectedPath) {
      const header = Array.from(root.querySelectorAll('[data-native-header]')).find(element => element.dataset.nativeHeader === selectedPath)?.getBoundingClientRect();
      const bounds = root.getBoundingClientRect();
      if (!header || header.top < bounds.top || header.bottom > bounds.bottom) {
        view.scrollTo({ type: 'item', id: selectedPath, align: 'start', behavior: 'instant' });
        view.render(true);
      }
    }
    syncChrome();
  },
};
root.addEventListener('scroll', () => { hoveredLine = undefined; scheduleChrome(); }, { passive: true });
for (const event of ['wheel', 'pointerdown', 'keydown', 'touchstart']) root.addEventListener(event, () => { interactionRevision++; }, { passive: true });
new ResizeObserver(scheduleChrome).observe(root);
window.addEventListener('pagehide', () => { view.cleanUp(); pool.terminate(); URL.revokeObjectURL(workerURL); });
window.addEventListener('error', event => {
  const location = event.filename && event.lineno ? ` (${event.filename}:${event.lineno}:${event.colno})` : '';
  post({ kind: 'error', message: (event.error?.message || event.message || 'Diff rendering failed. Refresh files to retry.') + location });
});
window.addEventListener('unhandledrejection', event => post({ kind: 'error', message: event.reason?.message || 'Diff rendering failed. Refresh files to retry.' }));

