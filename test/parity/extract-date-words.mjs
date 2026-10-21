// Writes lib/web/date_words.json: the month and weekday words the Angular app
// prints, taken from where Angular itself takes them, so Rails prints the
// same ones (Web::DateFormat). Re-run after an Angular or Chromium upgrade:
//
//   node test/parity/extract-date-words.mjs
//
// Two sources, because the Angular app uses two:
//   angular — DatePipe ("d MMM y"…): @angular/common's own CLDR locale data
//   intl    — Date#toLocaleDateString / Intl.DateTimeFormat: the browser's
//             ICU, read from the Playwright Chromium the parity suite runs
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const BACKEND = join(dirname(fileURLToPath(import.meta.url)), "../..");
const FRONTEND = join(BACKEND, "../frontend/node_modules/@angular/common");

// Angular's locale data arrays: [..., [format, standalone] month sets ...].
// ɵfindLocaleData / getLocaleMonthNames are the public API for reading them.
// @angular/common declares injectables that need the JIT compiler loaded first.
await import(join(FRONTEND, "../compiler/fesm2022/compiler.mjs"));
const common = await import(join(FRONTEND, "fesm2022/common.mjs"));
const { registerLocaleData, getLocaleMonthNames, getLocaleDayNames, getLocaleDateFormat, getLocaleTimeFormat, getLocaleDateTimeFormat, getLocaleDayPeriods, formatDate, FormStyle, TranslationWidth, FormatWidth } = common;
for (const id of ["fr", "ar"]) registerLocaleData((await import(join(FRONTEND, `locales/${id}.mjs`))).default, id);

// Every DatePipe pattern the pages use, formatted by Angular itself, for the
// Ruby side's spec to check itself against.
const PATTERNS = ["d MMM y", "dd/MM/yyyy", "dd/MM/yy", "dd/MM/yyyy HH:mm", "EEEE d MMMM y, HH:mm", "HH:mm", "mediumDate", "shortDate", "longDate", "shortTime", "medium", "short", "EEEE d MMMM", "d MMM", "d MMMM y", "fullDate", "EEE d MMM, HH:mm", "EEEE d MMMM, HH:mm"];
const INSTANTS = ["2026-10-05T07:03:00Z", "2026-03-14T21:47:00Z", "2026-12-31T12:00:00Z", "2026-01-01T00:09:00Z"];

const angular = {};
for (const id of ["fr", "en", "ar"]) {
  angular[id] = {
    samples: PATTERNS.flatMap((pattern) => INSTANTS.map((iso) => ({ pattern, iso, text: formatDate(iso, pattern, id, "+0000") }))),
    months_abbreviated: getLocaleMonthNames(id, FormStyle.Format, TranslationWidth.Abbreviated),
    months_wide: getLocaleMonthNames(id, FormStyle.Format, TranslationWidth.Wide),
    days_wide: getLocaleDayNames(id, FormStyle.Format, TranslationWidth.Wide),
    days_abbreviated: getLocaleDayNames(id, FormStyle.Format, TranslationWidth.Abbreviated),
    day_periods: getLocaleDayPeriods(id, FormStyle.Format, TranslationWidth.Abbreviated),
    // DatePipe's named formats ("mediumDate"…), as this locale spells them.
    formats: {
      shortDate: getLocaleDateFormat(id, FormatWidth.Short),
      mediumDate: getLocaleDateFormat(id, FormatWidth.Medium),
      longDate: getLocaleDateFormat(id, FormatWidth.Long),
      fullDate: getLocaleDateFormat(id, FormatWidth.Full),
      shortTime: getLocaleTimeFormat(id, FormatWidth.Short),
      // "medium" is the date and the time joined the way the locale joins
      // them (DatePipe's formatDateTime: {1} the date, {0} the time).
      medium: getLocaleDateTimeFormat(id, FormatWidth.Medium)
        .replace("{1}", getLocaleDateFormat(id, FormatWidth.Medium))
        .replace("{0}", getLocaleTimeFormat(id, FormatWidth.Medium)),
      short: getLocaleDateTimeFormat(id, FormatWidth.Short)
        .replace("{1}", getLocaleDateFormat(id, FormatWidth.Short))
        .replace("{0}", getLocaleTimeFormat(id, FormatWidth.Short)),
    },
  };
}

// The browser side: what the app's Intl calls return in each language the
// app can be in (ar is read as ar-TN, as LoginComponent#todayLabel asks).
const browser = await chromium.launch();
const page = await browser.newPage();
const intl = await page.evaluate(() => {
  // Each format the app calls, as its parts in order (formatToParts), with
  // the words and digits each part can take — order, punctuation, digits and
  // the clock all differ between languages, so a word list would not do.
  // `tags` says which locale the call names: the browser's own for
  // toLocaleDateString(undefined, …) (the page's language here, B-03, ar
  // read as ar-TN), or ngx-translate's currentLang for the notifications.
  const PAGE = { fr: "fr", en: "en", ar: "ar-TN" }
  const LANG = { fr: "fr", en: "en", ar: "ar" }
  const FORMATS = {
    // clients list "jusqu'au <date>"
    day_month_short: { tags: PAGE, options: { day: "numeric", month: "short" } },
    // the sign-in panel's day card (LoginComponent#todayLabel)
    weekday_day_month_long: { tags: PAGE, options: { weekday: "long", day: "numeric", month: "long" } },
    // notification-text.ts formatDate
    notification_date: { tags: LANG, options: { day: "2-digit", month: "long", year: "numeric" } },
    // notification-text.ts formatDateTime
    notification_datetime: { tags: LANG, options: { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" } },
    // TimeAgoPipe, past a week
    time_ago_date: { tags: LANG, options: { day: "2-digit", month: "short" } },
    // the dashboard's revenue chart: each month's label
    month_short: { tags: LANG, options: { month: "short" } },
    // the landing page's booking mock: each day's weekday (LandingComponent#bookingDays)
    weekday_short: { tags: PAGE, options: { weekday: "short" } },
  }
  const sampleAt = (h) => new Date(Date.UTC(2026, 9, 11, h, 5))
  const out = {}
  for (const id of ["fr", "en", "ar"]) {
    out[id] = {}
    for (const [name, { tags, options }] of Object.entries(FORMATS)) {
      const tag = tags[id]
      const fmt = new Intl.DateTimeFormat(tag, { timeZone: "UTC", ...options })
      const words = (type, dates) => dates.map((d) => fmt.formatToParts(d).find((p) => p.type === type)?.value ?? null)
      // 2026-10-11 is a Sunday, so weekday index = Date#getDay.
      out[id][name] = {
        tag,
        options,
        hour12: fmt.resolvedOptions().hour12 ?? false,
        parts: fmt.formatToParts(sampleAt(9)).map((p) => (p.type === "literal" ? { literal: p.value } : { type: p.type })),
        month: words("month", [...Array(12).keys()].map((m) => new Date(Date.UTC(2026, m, 11, 9)))),
        weekday: words("weekday", [...Array(7).keys()].map((d) => new Date(Date.UTC(2026, 9, 11 + d, 9)))),
        dayPeriod: options.hour ? { am: words("dayPeriod", [sampleAt(9)])[0], pm: words("dayPeriod", [sampleAt(21)])[0] } : null,
        // How this locale writes 0–9 (ar: Arabic-Indic; fr, en, ar-TN: Latin).
        digits: [...Array(10).keys()].map((n) => new Intl.NumberFormat(tag, { useGrouping: false }).format(n)),
        // Whole strings, for spec/lib/web/translations_spec.rb to check the
        // Ruby side against.
        samples: ["2026-10-05T07:03:00Z", "2026-03-14T21:47:00Z", "2026-12-31T12:00:00Z", "2026-01-01T00:09:00Z"].map((iso) => ({ iso, text: fmt.format(new Date(iso)) })),
      }
    }
  }
  // Number#toLocaleString(lang) (the dashboard's amounts): the digits, the
  // grouping and decimal marks, and how many fraction digits it keeps.
  out.numbers = {}
  // The page's language as a browser tag too: toLocaleString(undefined, …)
  // formats in the browser's own (B-03), ar read as ar-TN.
  const NUMBER_TAGS = { fr: "fr", en: "en", ar: "ar", "ar-TN": "ar-TN" }
  for (const id of Object.keys(NUMBER_TAGS)) {
    const fmt = new Intl.NumberFormat(NUMBER_TAGS[id])
    const parts = fmt.formatToParts(1234567.891)
    out.numbers[id] = {
      tag: NUMBER_TAGS[id],
      group: parts.find((p) => p.type === "group")?.value ?? "",
      decimal: parts.find((p) => p.type === "decimal")?.value ?? ".",
      digits: [...Array(10).keys()].map((n) => fmt.format(n)),
      min_grouping: fmt.format(1234).includes(parts.find((p) => p.type === "group")?.value ?? "§") ? 1 : 2,
      max_fraction: fmt.resolvedOptions().maximumFractionDigits,
      samples: [0, 7, 1234, 6000, 12345.5, 1234567.891, 0.125, 79, 230.5].map((n) => ({ n, text: (n).toLocaleString(NUMBER_TAGS[id]) })),
    }
  }
  return out
})
const numbers = intl.numbers;
delete intl.numbers;
const chromiumVersion = browser.version();
await browser.close();

writeFileSync(join(BACKEND, "lib/web/date_words.json"), JSON.stringify({
  "//": "Generated by test/parity/extract-date-words.mjs — do not edit.",
  sources: { angular_common: (await import(join(FRONTEND, "package.json"), { with: { type: "json" } })).default.version, chromium: chromiumVersion },
  angular,
  intl,
  numbers,
}, null, 2) + "\n");
console.log("wrote lib/web/date_words.json");
