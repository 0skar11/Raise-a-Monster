// Minimal Rojo-compatible place builder for this project's default.project.json
// usage (from the repo root): node tools/build-place.js [projectDir=.] [out=RaiseAMonster.rbxlx]
const fs = require("fs"), path = require("path");
const projectDir = process.argv[2] || ".";
const out = process.argv[3] || path.join(projectDir, "RaiseAMonster.rbxlx");
const project = JSON.parse(fs.readFileSync(path.join(projectDir, "default.project.json"), "utf8"));
let ref = 0;
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const ENUMS = { Technology: { Legacy: 0, Voxel: 1, Compatibility: 2, ShadowMap: 3, Future: 4 } };
function propXml(key, value, pad) {
  if (ENUMS[key]) {
    if (!(value in ENUMS[key])) throw new Error("unknown enum " + key + "." + value);
    return `${pad}<token name="${key}">${ENUMS[key][value]}</token>\n`;
  }
  if (typeof value === "boolean") return `${pad}<bool name="${key}">${value}</bool>\n`;
  if (typeof value === "number") return `${pad}<float name="${key}">${value}</float>\n`;
  return `${pad}<string name="${key}">${esc(String(value))}</string>\n`;
}
function readSrc(f) {
  const s = fs.readFileSync(f, "utf8").replace(/\r\n/g, "\n");
  if (s.includes("]]>")) throw new Error("]]> in " + f);
  return s;
}
function scriptClass(file) {
  if (/\.server\.luau?$/.test(file)) return "Script";
  if (/\.client\.luau?$/.test(file)) return "LocalScript";
  return "ModuleScript";
}
function item(cls, name, source, children, indent, props) {
  const pad = "  ".repeat(indent);
  let x = `${pad}<Item class="${cls}" referent="${ref++}">\n${pad}  <Properties>\n${pad}    <string name="Name">${esc(name)}</string>\n`;
  if (cls === "Script") x += `${pad}    <token name="RunContext">0</token>\n`;
  for (const [k, v] of Object.entries(props || {})) x += propXml(k, v, pad + "    ");
  if (source !== null) x += `${pad}    <string name="Source"><![CDATA[${source}]]></string>\n`;
  x += `${pad}  </Properties>\n`;
  for (const c of children) x += c(indent + 1);
  x += `${pad}</Item>\n`;
  return x;
}
// .rbxmx model files are embedded as-is (their referents are unique RBX… ids);
// their <SharedStrings> are collected and written once at the end of the place.
const sharedStrings = [];
function embedRbxmx(p, name) {
  const xml = fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n");
  const start = xml.indexOf("<Item ");
  const sharedAt = xml.indexOf("<SharedStrings>");
  const end = xml.lastIndexOf("</Item>", sharedAt >= 0 ? sharedAt : xml.length) + "</Item>".length;
  if (start < 0 || end < start) throw new Error("bad rbxmx " + p);
  if (sharedAt >= 0) {
    const close = xml.indexOf("</SharedStrings>", sharedAt);
    sharedStrings.push(xml.slice(sharedAt + "<SharedStrings>".length, close));
  }
  let body = xml.slice(start, end);
  // the root keeps its own name unless the project gives it another one
  if (name) body = body.replace(/<string name="Name">[^<]*<\/string>/, `<string name="Name">${esc(name)}</string>`);
  return body + "\n";
}
function fromPath(p, name) {
  return (indent) => {
    const st = fs.statSync(p);
    if (st.isFile() && p.endsWith(".rbxmx")) return embedRbxmx(p, name);
    if (st.isFile()) {
      const base = path.basename(p).replace(/(\.server|\.client)?\.luau?$/, "");
      return item(scriptClass(p), name ?? base, readSrc(p), [], indent);
    }
    const entries = fs.readdirSync(p).sort();
    const init = entries.find((e) => /^init(\.server|\.client)?\.luau?$/.test(e));
    const kids = entries
      .filter((e) => e !== init && (/\.luau?$/.test(e) || fs.statSync(path.join(p, e)).isDirectory()))
      .map((e) => fromPath(path.join(p, e)));
    if (init) return item(scriptClass(init), name, readSrc(path.join(p, init)), kids, indent);
    return item("Folder", name, null, kids, indent);
  };
}
function node(name, def, indent) {
  const keys = Object.keys(def).filter((k) => !k.startsWith("$"));
  if (def.$path) return fromPath(path.join(projectDir, def.$path), name)(indent);
  const cls = def.$className || name;
  return item(cls, name, null, keys.map((k) => (i) => node(k, def[k], i)), indent, def.$properties);
}
let xml = '<roblox version="4">\n';
for (const k of Object.keys(project.tree).filter((k) => !k.startsWith("$"))) xml += node(k, project.tree[k], 1);
if (sharedStrings.length) xml += "<SharedStrings>" + sharedStrings.join("") + "</SharedStrings>\n";
xml += "</roblox>";
fs.writeFileSync(out, xml);
console.log("wrote", out, xml.length);
