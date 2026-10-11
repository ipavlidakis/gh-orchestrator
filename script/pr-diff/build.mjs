import { build } from 'esbuild';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const settings = {
  absWorkingDir: root, bundle: true, minify: true, format: 'iife', target: 'safari18',
  legalComments: 'inline', metafile: true, define: { 'process.env.NODE_ENV': '"production"' },
};
settings.plugins = [{ name: 'local-shiki', setup(builder) {
  builder.onResolve({ filter: /^shiki$/ }, () => ({ path: path.join(root, 'shiki-local.js') }));
  builder.onLoad({ filter: /@pierre\/diffs\/dist\/components\/CodeView\.js$/ }, async ({ path: file }) => {
    const source = await readFile(file, 'utf8');
    const immediateResize = 'if (shouldRender) this.render(true);';
    if (source.split(immediateResize).length !== 2) throw new Error('Recheck Pierre resize scheduling before upgrading the renderer.');
    // Queue layout writes outside ResizeObserver delivery to prevent WebKit resize loops.
    return { contents: source.replace(immediateResize, 'if (shouldRender) this.render();'), loader: 'js' };
  });
} }];
const worker = await build({ ...settings, entryPoints: ['node_modules/@pierre/diffs/dist/worker/worker.js'], write: false, legalComments: 'inline' });
const renderer = await build({ ...settings, entryPoints: ['index.js'],
  outfile: '../../App/Resources/PRDiff.js',
  define: { ...settings.define, __DIFF_WORKER_SOURCE__: JSON.stringify(worker.outputFiles[0].text) },
});
const packages = new Set([...Object.keys(worker.metafile.inputs), ...Object.keys(renderer.metafile.inputs)]
  .map(input => input.match(/^node_modules\/(?:@[^/]+\/)?[^/]+/)?.[0]).filter(Boolean));
const notices = [];
for (const directory of [...packages].sort()) {
  const location = path.join(root, directory);
  const metadata = JSON.parse(await readFile(path.join(location, 'package.json'), 'utf8'));
  const licenses = (await readdir(location)).filter(name => /^(license|licence|copying|notice)(\.|$)/i.test(name));
  const texts = await Promise.all(licenses.map(name => readFile(path.join(location, name), 'utf8')));
  notices.push(`${metadata.name}@${metadata.version} (${metadata.license ?? 'See license below'})\n${texts.join('\n')}`);
}
await writeFile(path.join(root, '../../App/Resources/PRDiff-LICENSE.txt'), notices.join('\n\n--------------------\n\n'));
console.log('Bundled @pierre/diffs 1.5.2 and one local highlighting worker.');
