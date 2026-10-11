export * from 'shiki/core';
export { createHighlighterCore as createHighlighter } from 'shiki/core';
export { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
export { createOnigurumaEngine } from 'shiki/engine/oniguruma';

export const bundledLanguages = {
  swift: () => import('shiki/langs/swift.mjs'),
  kotlin: () => import('shiki/langs/kotlin.mjs'),
  javascript: () => import('shiki/langs/javascript.mjs'),
  typescript: () => import('shiki/langs/typescript.mjs'),
  tsx: () => import('shiki/langs/tsx.mjs'),
  jsx: () => import('shiki/langs/jsx.mjs'),
  json: () => import('shiki/langs/json.mjs'),
  python: () => import('shiki/langs/python.mjs'),
  css: () => import('shiki/langs/css.mjs'),
  html: () => import('shiki/langs/html.mjs'),
  markdown: () => import('shiki/langs/markdown.mjs'),
  shellscript: () => import('shiki/langs/shellscript.mjs'),
  yaml: () => import('shiki/langs/yaml.mjs'),
};
