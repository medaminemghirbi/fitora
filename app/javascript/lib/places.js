// core/models/countries.ts, timezones.ts and currency.ts, ported as they
// are: the company setup page builds its country, timezone and currency
// options in the browser, from the browser's Intl, as the Angular page does
// (French country names, GMT offsets as of now). Keep in step with the
// Angular files while both exist.

// ---- countries ---------------------------------------------------------------

// prettier-ignore
const CODES = [
  "AD","AE","AF","AG","AI","AL","AM","AO","AR","AT","AU","AW","AZ",
  "BA","BB","BD","BE","BF","BG","BH","BI","BJ","BL","BM","BN","BO","BQ","BR","BS","BT","BW","BY","BZ",
  "CA","CD","CF","CG","CH","CI","CK","CL","CM","CN","CO","CR","CU","CV","CW","CY","CZ",
  "DE","DJ","DK","DM","DO","DZ",
  "EC","EE","EG","EH","ER","ES","ET",
  "FI","FJ","FK","FM","FO","FR",
  "GA","GB","GD","GE","GF","GG","GH","GI","GL","GM","GN","GP","GQ","GR","GT","GU","GW","GY",
  "HK","HN","HR","HT","HU",
  "ID","IE","IL","IM","IN","IQ","IR","IS","IT",
  "JE","JM","JO","JP",
  "KE","KG","KH","KI","KM","KN","KP","KR","KW","KY","KZ",
  "LA","LB","LC","LI","LK","LR","LS","LT","LU","LV","LY",
  "MA","MC","MD","ME","MF","MG","MH","MK","ML","MM","MN","MO","MP","MQ","MR","MS","MT","MU","MV","MW","MX","MY","MZ",
  "NA","NC","NE","NG","NI","NL","NO","NP","NR","NU","NZ",
  "OM",
  "PA","PE","PF","PG","PH","PK","PL","PM","PR","PS","PT","PW","PY",
  "QA",
  "RE","RO","RS","RU","RW",
  "SA","SB","SC","SD","SE","SG","SH","SI","SK","SL","SM","SN","SO","SR","SS","ST","SV","SX","SY","SZ",
  "TC","TD","TG","TH","TJ","TL","TM","TN","TO","TR","TT","TV","TW","TZ",
  "UA","UG","US","UY","UZ",
  "VA","VC","VE","VG","VI","VN","VU",
  "WF","WS",
  "YE","YT",
  "ZA","ZM","ZW",
]

function flag(code) {
  if (!/^[A-Z]{2}$/.test(code)) return ""
  return String.fromCodePoint(...[...code].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65))
}

const regionNames = (() => {
  try {
    return new Intl.DisplayNames(["fr"], { type: "region", fallback: "code" })
  } catch {
    return null
  }
})()

const countryName = (code) => regionNames?.of(code) ?? code

export const COUNTRIES = CODES.map((code) => ({ code, name: countryName(code), flag: flag(code) }))
  .sort((a, b) => a.name.localeCompare(b.name, "fr", { sensitivity: "base" }))

const BY_CODE = new Map(COUNTRIES.map((c) => [c.code, c]))
const BY_NAME = new Map(COUNTRIES.map((c) => [c.name.toLowerCase(), c]))

// toCountryCode: an alpha-2 code, a French name or a legacy English name →
// the canonical alpha-2 code ("" when nothing matches).
export function toCountryCode(value) {
  if (!value) return ""
  const v = value.trim()
  if (BY_CODE.has(v.toUpperCase())) return v.toUpperCase()
  if (BY_NAME.has(v.toLowerCase())) return BY_NAME.get(v.toLowerCase()).code
  try {
    const en = new Intl.DisplayNames(["en"], { type: "region", fallback: "code" })
    const hit = COUNTRIES.find((c) => en.of(c.code)?.toLowerCase() === v.toLowerCase())
    if (hit) return hit.code
  } catch {
    // Intl.DisplayNames unavailable — fall through
  }
  return ""
}

// ---- timezones -----------------------------------------------------------------

const ZONES = [
  {
    region: "Afrique",
    ids: [
      ["Africa/Tunis", "TN"], ["Africa/Casablanca", "MA"], ["Africa/Algiers", "DZ"], ["Africa/Cairo", "EG"],
      ["Africa/Tripoli", "LY"], ["Africa/Khartoum", "SD"], ["Africa/Dakar", "SN"], ["Africa/Abidjan", "CI"],
      ["Africa/Bamako", "ML"], ["Africa/Nouakchott", "MR"], ["Africa/Ouagadougou", "BF"], ["Africa/Niamey", "NE"],
      ["Africa/Lome", "TG"], ["Africa/Cotonou", "BJ"], ["Africa/Conakry", "GN"], ["Africa/Lagos", "NG"],
      ["Africa/Kinshasa", "CD"], ["Africa/Douala", "CM"], ["Africa/Libreville", "GA"], ["Africa/Brazzaville", "CG"],
      ["Africa/Nairobi", "KE"], ["Africa/Addis_Ababa", "ET"], ["Africa/Kigali", "RW"], ["Africa/Bujumbura", "BI"],
      ["Africa/Johannesburg", "ZA"], ["Africa/Maputo", "MZ"], ["Indian/Antananarivo", "MG"], ["Indian/Mauritius", "MU"],
    ],
  },
  {
    region: "Europe",
    ids: [
      ["Europe/Paris", "FR"], ["Europe/London", "GB"], ["Europe/Brussels", "BE"], ["Europe/Madrid", "ES"],
      ["Europe/Lisbon", "PT"], ["Europe/Rome", "IT"], ["Europe/Berlin", "DE"], ["Europe/Amsterdam", "NL"],
      ["Europe/Zurich", "CH"], ["Europe/Vienna", "AT"], ["Europe/Luxembourg", "LU"], ["Europe/Athens", "GR"],
      ["Europe/Bucharest", "RO"], ["Europe/Istanbul", "TR"], ["Europe/Moscow", "RU"], ["Europe/Dublin", "IE"],
      ["Europe/Stockholm", "SE"], ["Europe/Oslo", "NO"], ["Europe/Copenhagen", "DK"], ["Europe/Warsaw", "PL"],
      ["Europe/Kyiv", "UA"],
    ],
  },
  {
    region: "Moyen-Orient",
    ids: [
      ["Asia/Riyadh", "SA"], ["Asia/Dubai", "AE"], ["Asia/Qatar", "QA"], ["Asia/Kuwait", "KW"],
      ["Asia/Bahrain", "BH"], ["Asia/Muscat", "OM"], ["Asia/Beirut", "LB"], ["Asia/Amman", "JO"],
      ["Asia/Jerusalem", "IL"], ["Asia/Damascus", "SY"], ["Asia/Baghdad", "IQ"], ["Asia/Tehran", "IR"],
    ],
  },
  {
    region: "Amériques",
    ids: [
      ["America/New_York", "US"], ["America/Chicago", "US"], ["America/Denver", "US"], ["America/Los_Angeles", "US"],
      ["America/Toronto", "CA"], ["America/Vancouver", "CA"], ["America/Mexico_City", "MX"], ["America/Sao_Paulo", "BR"],
      ["America/Argentina/Buenos_Aires", "AR"], ["America/Santiago", "CL"], ["America/Bogota", "CO"], ["America/Lima", "PE"],
    ],
  },
  {
    region: "Asie / Pacifique",
    ids: [
      ["Asia/Karachi", "PK"], ["Asia/Kolkata", "IN"], ["Asia/Dhaka", "BD"], ["Asia/Bangkok", "TH"],
      ["Asia/Singapore", "SG"], ["Asia/Kuala_Lumpur", "MY"], ["Asia/Jakarta", "ID"], ["Asia/Hong_Kong", "HK"],
      ["Asia/Shanghai", "CN"], ["Asia/Tokyo", "JP"], ["Asia/Seoul", "KR"], ["Australia/Sydney", "AU"],
      ["Pacific/Auckland", "NZ"],
    ],
  },
]

const EXTRA_TZ_COUNTRY = {
  "Europe/Madrid": "ES", "Europe/Prague": "CZ", "Europe/Budapest": "HU", "Europe/Sofia": "BG",
  "Europe/Helsinki": "FI", "Europe/Belgrade": "RS", "Europe/Zagreb": "HR", "Europe/Bratislava": "SK",
  "Europe/Ljubljana": "SI", "Europe/Vilnius": "LT", "Europe/Riga": "LV", "Europe/Tallinn": "EE",
  "America/Phoenix": "US", "America/Anchorage": "US", "America/Detroit": "US", "America/Halifax": "CA",
  "America/Edmonton": "CA", "America/Winnipeg": "CA", "America/Montreal": "CA", "America/Tijuana": "MX",
  "America/Monterrey": "MX", "America/Caracas": "VE", "America/Montevideo": "UY", "America/Guayaquil": "EC",
  "Australia/Melbourne": "AU", "Australia/Brisbane": "AU", "Australia/Perth": "AU", "Australia/Adelaide": "AU",
  "Asia/Manila": "PH", "Asia/Ho_Chi_Minh": "VN", "Asia/Taipei": "TW", "Asia/Colombo": "LK",
  "Africa/Accra": "GH", "Africa/Luanda": "AO", "Africa/Dar_es_Salaam": "TZ", "Africa/Kampala": "UG",
  "Africa/Lusaka": "ZM", "Africa/Harare": "ZW", "Africa/Windhoek": "NA", "Africa/Gaborone": "BW",
}

const TZ_COUNTRY = { ...EXTRA_TZ_COUNTRY }
const COUNTRY_TZ = {}
for (const g of ZONES) {
  for (const [id, cc] of g.ids) {
    TZ_COUNTRY[id] = cc
    if (!COUNTRY_TZ[cc]) COUNTRY_TZ[cc] = id
  }
}

function gmtOffset(tz) {
  try {
    const part = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "shortOffset" })
      .formatToParts(new Date())
      .find((p) => p.type === "timeZoneName")
    return part?.value.replace("GMT", "UTC") ?? ""
  } catch {
    return ""
  }
}

const cityName = (tz) => tz.split("/").pop().replace(/_/g, " ")

export const TIMEZONE_GROUPS = ZONES.map((g) => ({
  region: g.region,
  zones: g.ids.map(([id]) => {
    const off = gmtOffset(id)
    return { value: id, label: off ? `${cityName(id)} (${off})` : cityName(id) }
  }),
}))

const ALL = new Set(TIMEZONE_GROUPS.flatMap((g) => g.zones.map((z) => z.value)))

export function browserTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "Africa/Tunis"
  } catch {
    return "Africa/Tunis"
  }
}

export const countryForTimezone = (tz) => (tz && TZ_COUNTRY[tz]) || ""
export const timezoneForCountry = (code) => (code && COUNTRY_TZ[code.toUpperCase()]) || ""

// From the browser timezone alone; Tunisia when the zone is unknown.
export function guessLocation() {
  const timezone = browserTimezone()
  return { timezone, country: countryForTimezone(timezone) || "TN" }
}

// An off-list timezone first, so the user always sees their current value.
export function ensureTimezone(tz) {
  if (!tz || ALL.has(tz)) return TIMEZONE_GROUPS
  const off = gmtOffset(tz)
  return [{ region: "—", zones: [{ value: tz, label: off ? `${cityName(tz)} (${off})` : cityName(tz) }] }, ...TIMEZONE_GROUPS]
}

// ---- currencies ------------------------------------------------------------------

export const CURRENCIES = [
  { code: "TND", symbol: "DT", name: "Dinar tunisien" },
  { code: "MAD", symbol: "DH", name: "Dirham marocain" },
  { code: "DZD", symbol: "DA", name: "Dinar algérien" },
  { code: "EGP", symbol: "E£", name: "Livre égyptienne" },
  { code: "EUR", symbol: "€", name: "Euro" },
  { code: "USD", symbol: "$", name: "Dollar américain" },
  { code: "GBP", symbol: "£", name: "Livre sterling" },
  { code: "CHF", symbol: "CHF", name: "Franc suisse" },
  { code: "CAD", symbol: "CA$", name: "Dollar canadien" },
  { code: "SAR", symbol: "SAR", name: "Riyal saoudien" },
  { code: "AED", symbol: "AED", name: "Dirham des Émirats" },
  { code: "QAR", symbol: "QAR", name: "Riyal qatari" },
  { code: "XOF", symbol: "FCFA", name: "Franc CFA (UEMOA)" },
]
