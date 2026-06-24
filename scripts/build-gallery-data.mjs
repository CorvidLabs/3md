// Build web/gallery-data.json from every file in Examples/. Each entry carries
// {slug, axis, title, category, src}. Category is taken from the file's own
// `category:` frontmatter when present (authoritative); otherwise it is inferred
// from the slug, title, and axis. Run from the repo root:
//   node scripts/build-gallery-data.mjs
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { parse } from "../js/src/index.ts";

// Canonical category set surfaced in the gallery UI.
export const CATEGORIES = [
  "Games", "Animation", "Data", "Information", "Notes", "Education",
  "Business", "Creative", "Health", "Home", "Maps", "Story", "Engineering",
];

// Ordered keyword rules: first match wins, so put specific before general.
const RULES = [
  ["Games", /\b(game|chess|dungeon|quest|puzzle|catan|bracket|rpg|arcade|snake|maze|tournament|playbook|play-?by-?play|soccer|leaderboard|boss|dice)\b/],
  ["Health", /\b(med|ecg|vitals?|workout|yoga|breath|triage|patient|heart|symptom|nutrition|recovery|therapy|fitness|marathon|wellness|sleep|pulse|dose|clinical|diagnos)\b/],
  ["Maps", /\b(map|itinerary|route|road-?trip|transit|seating|parking|topo|trail|metro|coast|directions|floor-?plan|dive)\b/],
  ["Animation", /\b(animation|bounce|sprite|walk-?cycle|marquee|spinner|loading|cursor|typing|wave|beat|orbit|growth|frame)\b/],
  ["Story", /\b(story|poem|stanza|novel|scene|comic|storyboard|fable|tale|verse|chapter|sermon|joke|punchline|toast)\b/],
  ["Creative", /\b(art|voxel|paint|album|design-?system|music|sheet|song|melody|palette|colou?r|sketch|photo|portrait|theme)\b/],
  ["Education", /\b(edu|lesson|syllabus|course|flash-?card|tutorial|theorem|proof|study|vocab|grammar|alphabet|periodic|quiz|learn|spanish|language|skill|translation)\b/],
  ["Business", /\b(biz|pitch|road-?map|budget|sales|invoice|quarterly|okr|kpi|deck|startup|revenue|finance|expense|resume|strategy|proposal|funnel)\b/],
  ["Engineering", /\b(api|schema|pipeline|migration|ci-?cd|deploy|server|rack|architecture|wireframe|dag|infra|kubernetes|database|git|threat|incident|attack|security|devops|code-?review|refactor|state-?machine|protocol|redacted)\b/],
  ["Data", /\b(data|dashboard|forecast|weather|status|metrics?|chart|stats?|report|analytics|tide|rain|telemetry|monitor|sensor|traffic)\b/],
  ["Home", /\b(home|recipe|latte|coffee|dinner|knit|garden|maintenance|assembly|bookshelf|grocery|wedding|household|car|dishcloth)\b/],
  ["Notes", /\b(note|journal|diary|tasting|wine|todo|checklist|planner|meeting|minutes|daily|reflection|podcast)\b/],
  ["Information", /\b(solar|history|timeline|museum|encyclopedia|fact|guide|reference|wiki|anatomy|explained|annotated|building|rocket|space)\b/],
];

function categorize(slug, title, axis, declared) {
  if (declared && CATEGORIES.includes(declared)) return declared;
  const hay = `${slug} ${title}`.toLowerCase();
  for (const [cat, re] of RULES) if (re.test(hay)) return cat;
  if (axis === "frame") return "Animation";
  if (axis === "slide") return "Business";
  if (axis === "space" || axis === "depth" || axis === "floor") return "Information";
  return "Information";
}

const dir = "Examples";
const files = readdirSync(dir).filter((f) => f.endsWith(".3md")).sort();
const out = [];
const counts = {};
for (const f of files) {
  const slug = f.replace(/\.3md$/, "");
  const src = readFileSync(`${dir}/${f}`, "utf8");
  let doc;
  try { doc = parse(src); }
  catch (e) { console.warn(`skip (parse error): ${slug}: ${e.message}`); continue; }
  const title = doc.title || doc.metadata.title || slug;
  const category = categorize(slug, title, doc.axis, doc.metadata.category);
  counts[category] = (counts[category] || 0) + 1;
  out.push({ slug, axis: doc.axis, title, category, src });
}
writeFileSync("web/gallery-data.json", JSON.stringify(out));
console.log(`gallery-data.json: ${out.length} entries`);
console.log("by category:", JSON.stringify(counts, null, 0));
