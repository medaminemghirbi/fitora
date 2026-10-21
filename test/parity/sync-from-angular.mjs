// Keeps the Rails UI's copies of the Angular styles and translations
// identical to the Angular source while both exist (MIGRATION_AUDIT §11.1).
//
//   node test/parity/sync-from-angular.mjs --write   copy from ../frontend
//   node test/parity/sync-from-angular.mjs           check only (exit 1 on drift)
//
// What is copied:
//   frontend/src/styles/**          → app/assets/stylesheets/fitora/styles/**  (verbatim)
//   frontend/src/styles.scss        → app/assets/stylesheets/fitora/_root.scss (one line differs, see ROOT_EDITS)
//   every component in ng/manifest.json → app/assets/stylesheets/ng/<id>.scss (verbatim; inline
//   `styles: [`…`]` extracted from the component's TypeScript)
//   frontend/src/assets/i18n/*.json → config/locales/web/ng/*.json             (verbatim)
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const BACKEND = join(dirname(fileURLToPath(import.meta.url)), "../..");
const FRONTEND = process.env.FITORA_FRONTEND ?? join(BACKEND, "../frontend");
const SHEETS = join(BACKEND, "app/assets/stylesheets");
const write = process.argv.includes("--write");

// Sass never loads an @import whose URL ends in ".css" — it passes it through
// to the browser as a plain CSS import. Angular's builder inlines it instead,
// so the copy names the file without its extension, which Sass does inline.
const ROOT_EDITS = [[`@import "bootstrap-icons/font/bootstrap-icons.css";`, `@import "bootstrap-icons/font/bootstrap-icons";`]];

const HEADER = (src) => `// GENERATED from frontend/${src} by test/parity/sync-from-angular.mjs — edit the Angular source, then run it with --write.\n`;

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

function inlineStyles(tsPath) {
  const ts = readFileSync(tsPath, "utf8");
  const block = ts.match(/styles:\s*\[([\s\S]*?)\]\s*,?\s*\n\s*\}\)/);
  if (!block) throw new Error(`no styles: [...] in ${tsPath}`);
  const parts = [...block[1].matchAll(/`([\s\S]*?)`/g)].map((m) => m[1]);
  if (parts.length === 0) throw new Error(`no template literal in styles of ${tsPath}`);
  return parts.join("\n");
}

const expected = new Map(); // destination → content

for (const file of walk(join(FRONTEND, "src/styles"))) {
  const rel = relative(join(FRONTEND, "src/styles"), file);
  expected.set(join(SHEETS, "fitora/styles", rel), HEADER(`src/styles/${rel}`) + readFileSync(file, "utf8"));
}

let root = readFileSync(join(FRONTEND, "src/styles.scss"), "utf8");
for (const [from, to] of ROOT_EDITS) {
  if (!root.includes(from)) throw new Error(`styles.scss no longer contains: ${from}`);
  root = root.replace(from, to);
}
expected.set(join(SHEETS, "fitora/_root.scss"), HEADER("src/styles.scss") + root);

const manifest = JSON.parse(readFileSync(join(SHEETS, "ng/manifest.json"), "utf8"));
// A component stylesheet that @uses another by a relative path (the member's
// profile reuses the schedule's) names the copy of that one instead: Sass
// then emits it inside this stylesheet, scoped as this component, as
// Angular's build does.
const idBySource = new Map(Object.entries(manifest.components).flatMap(([id, { source }]) => (Array.isArray(source) ? [] : [[source, id]])));
function relink(css, file) {
  return css.replace(/@use "(\.\.?\/[^"]+)";/g, (_, url) => {
    const target = relative(join(FRONTEND, "src/app"), join(FRONTEND, "src/app", dirname(file), url));
    const id = idBySource.get(target);
    if (!id) throw new Error(`${file} @uses ${url}, which no manifest entry copies`);
    return `@use "ng/${id}";`;
  });
}
// `source` may list several files, as a component's styleUrls does: Angular
// concatenates them in order.
for (const [id, { source, inline }] of Object.entries(manifest.components)) {
  const sources = Array.isArray(source) ? source : [source];
  const css = sources.map((file) => {
    const src = join(FRONTEND, "src/app", file);
    return inline ? inlineStyles(src) : relink(readFileSync(src, "utf8"), file);
  }).join("\n");
  expected.set(join(SHEETS, "ng", `${id}.scss`), HEADER(sources.map((f) => `src/app/${f}`).join(" + ")) + css);
}

// JSON has no comments, so the translations are copied as they are.
for (const locale of ["fr", "en", "ar"]) {
  expected.set(join(BACKEND, "config/locales/web/ng", `${locale}.json`), readFileSync(join(FRONTEND, "src/assets/i18n", `${locale}.json`), "utf8"));
}

// app/javascript/lib/places.js ports the setup page's country, timezone and
// currency lists: their data must be the Angular files' own (semicolons aside).
const places = readFileSync(join(BACKEND, "app/javascript/lib/places.js"), "utf8");
const block = (text, start, end = "]\n") => {
  const plain = text.replaceAll(";", "");
  const at = plain.indexOf(start);
  if (at < 0) return null;
  // The TypeScript's type annotation aside: `const ZONES: {…}[] = [` → `const ZONES = [`.
  return plain.slice(at, plain.indexOf(end, at) + end.length).replace(/^([^=\n]*?):\s[^=]+=/, "$1 =");
};
const models = join(FRONTEND, "src/app/core/models");
const PORTED = [
  ["countries.ts", "const CODES"], ["timezones.ts", "const ZONES"], ["timezones.ts", "const EXTRA_TZ_COUNTRY", "}\n"], ["currency.ts", "export const CURRENCIES"],
];
let portDrift = 0;
for (const [file, start, end] of PORTED) {
  const source = block(readFileSync(join(models, file), "utf8"), start, end);
  if (source === null || source !== block(places, start, end)) {
    portDrift += 1;
    console.error(`differs: app/javascript/lib/places.js (${start} from ${file}) — port it again by hand`);
  }
}

let drift = portDrift;
for (const [dest, content] of expected) {
  const current = existsSync(dest) ? readFileSync(dest, "utf8") : null;
  if (current === content) continue;
  if (write) {
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, content);
    console.log(`wrote ${relative(BACKEND, dest)}`);
  } else {
    drift += 1;
    console.error(`${current === null ? "missing" : "differs"}: ${relative(BACKEND, dest)}`);
  }
}
if (drift) {
  console.error(`\n${drift} file(s) out of sync with the Angular source — run: node test/parity/sync-from-angular.mjs --write`);
  process.exit(1);
}
console.log(`${expected.size} files ${write ? "in sync" : "match the Angular source"}.`);
