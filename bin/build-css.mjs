#!/usr/bin/env node
// Builds the web UI's stylesheets (cssbundling-rails runs this as
// `npm run build:css`, also during assets:precompile).
//
//   app/assets/builds/application.css    the global layer: Fitora's design
//                                         system, copied from the Angular app
//   app/assets/builds/ng-components.css  each Angular component's own styles,
//                                         scoped exactly as Angular's emulated
//                                         encapsulation scopes them
//
// The second file is why this is a script and not a sass one-liner. Angular
// rewrites every selector in a component stylesheet so it only matches that
// component's own template — `.rail-item` becomes `.rail-item[_ngcontent-X]`
// — which also raises its specificity. Copying the rules unscoped would let
// them leak into other components and lose cascade fights they win today.
// So the build runs Angular's own algorithm (`encapsulateStyle` from
// @angular/compiler, the version the Angular app uses), and the ERB handler
// in lib/web/angular_template.rb puts the matching attributes on the
// elements. Pass --watch to rebuild on change.
import { readFileSync, writeFileSync, watch } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as sass from "sass";
import { encapsulateStyle } from "@angular/compiler";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SHEETS = join(ROOT, "app/assets/stylesheets");
const BUILDS = join(ROOT, "app/assets/builds");
const options = {
  loadPaths: [join(ROOT, "node_modules"), SHEETS],
  style: "expanded",
  // The Angular app compiles with this same Sass (1.71.1, pinned in
  // package.json), so the CSS that comes out is the CSS it ships.
  quietDeps: true,
};

function build() {
  const started = Date.now();
  writeFileSync(join(BUILDS, "application.css"), sass.compile(join(SHEETS, "application.scss"), options).css);

  const { components } = JSON.parse(readFileSync(join(SHEETS, "ng/manifest.json"), "utf8"));
  const scoped = Object.keys(components).map((id) => {
    const css = sass.compile(join(SHEETS, "ng", `${id}.scss`), options).css;
    return `/* ${id} */\n${encapsulateStyle(css).replaceAll("%COMP%", id)}`;
  });
  writeFileSync(join(BUILDS, "ng-components.css"), scoped.join("\n\n") + "\n");
  console.log(`css built in ${Date.now() - started} ms (${scoped.length} components)`);
}

build();

if (process.argv.includes("--watch")) {
  let timer;
  watch(SHEETS, { recursive: true }, () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      try { build(); } catch (error) { console.error(error.message); }
    }, 100);
  });
}
