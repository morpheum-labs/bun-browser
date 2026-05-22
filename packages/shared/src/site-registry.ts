/**
 * Site adapter registry — scan ~/.bun-browser/claw-bun-mcp and local overrides.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { DAEMON_DIR } from "./daemon-client.js";
import { resolveCommunitySitesDir } from "./community-sites-path.js";

export interface SiteArgDef {
  required?: boolean;
  description?: string;
}

export interface SiteMeta {
  name: string;
  description: string;
  domain: string;
  args: Record<string, SiteArgDef>;
  capabilities?: string[];
  readOnly?: boolean;
  example?: string;
  filePath: string;
  source: "local" | "community";
}

export function getLocalSitesDir(baseDir: string = DAEMON_DIR): string {
  return join(baseDir, "sites");
}

export function getCommunitySitesDir(baseDir: string = DAEMON_DIR): string {
  return resolveCommunitySitesDir(baseDir);
}

export function parseSiteMeta(
  filePath: string,
  source: "local" | "community",
  baseDir: string = DAEMON_DIR,
): SiteMeta | null {
  let content: string;
  try {
    content = readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }

  const sitesDir = source === "local" ? getLocalSitesDir(baseDir) : getCommunitySitesDir(baseDir);
  const relPath = relative(sitesDir, filePath);
  const defaultName = relPath.replace(/\.js$/, "").replace(/\\/g, "/");

  const metaMatch = content.match(/\/\*\s*@meta\s*\n([\s\S]*?)\*\//);
  if (metaMatch) {
    try {
      const metaJson = JSON.parse(metaMatch[1]) as Partial<SiteMeta>;
      return {
        name: metaJson.name || defaultName,
        description: metaJson.description || "",
        domain: metaJson.domain || "",
        args: metaJson.args || {},
        capabilities: metaJson.capabilities,
        readOnly: metaJson.readOnly,
        example: metaJson.example,
        filePath,
        source,
      };
    } catch {
      // fall through to @tag format
    }
  }

  const meta: SiteMeta = {
    name: defaultName,
    description: "",
    domain: "",
    args: {},
    filePath,
    source,
  };

  const tagPattern = /\/\/\s*@(\w+)[ \t]+(.*)/g;
  let match: RegExpExecArray | null;
  while ((match = tagPattern.exec(content)) !== null) {
    const [, key, value] = match;
    switch (key) {
      case "name":
        meta.name = value.trim();
        break;
      case "description":
        meta.description = value.trim();
        break;
      case "domain":
        meta.domain = value.trim();
        break;
      case "args":
        for (const arg of value.trim().split(/[,\s]+/).filter(Boolean)) {
          meta.args[arg] = { required: true };
        }
        break;
      case "example":
        meta.example = value.trim();
        break;
    }
  }

  return meta;
}

export function scanSites(
  dir: string,
  source: "local" | "community",
  baseDir: string = DAEMON_DIR,
): SiteMeta[] {
  if (!existsSync(dir)) return [];
  const sites: SiteMeta[] = [];

  function walk(currentDir: string): void {
    let entries;
    try {
      entries = readdirSync(currentDir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory() && !entry.name.startsWith(".")) {
        walk(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".js")) {
        const meta = parseSiteMeta(fullPath, source, baseDir);
        if (meta) sites.push(meta);
      }
    }
  }

  walk(dir);
  return sites;
}

/** All adapters — local overrides win over community. */
export function getAllSites(baseDir: string = DAEMON_DIR): SiteMeta[] {
  const community = scanSites(getCommunitySitesDir(baseDir), "community", baseDir);
  const local = scanSites(getLocalSitesDir(baseDir), "local", baseDir);

  const byName = new Map<string, SiteMeta>();
  for (const site of community) byName.set(site.name, site);
  for (const site of local) byName.set(site.name, site);

  return Array.from(byName.values()).sort((a, b) => a.name.localeCompare(b.name));
}

export function findSite(name: string, baseDir: string = DAEMON_DIR): SiteMeta | undefined {
  return getAllSites(baseDir).find((site) => site.name === name);
}

export function searchSites(query: string, baseDir: string = DAEMON_DIR): SiteMeta[] {
  const q = query.toLowerCase();
  return getAllSites(baseDir).filter(
    (site) =>
      site.name.toLowerCase().includes(q) ||
      site.description.toLowerCase().includes(q) ||
      site.domain.toLowerCase().includes(q),
  );
}

export function siteInfoPayload(site: SiteMeta): Record<string, unknown> {
  return {
    name: site.name,
    description: site.description,
    domain: site.domain,
    args: site.args,
    example: site.example,
    readOnly: site.readOnly,
    capabilities: site.capabilities,
    source: site.source,
  };
}

export function siteListPayload(baseDir: string = DAEMON_DIR): Array<Record<string, unknown>> {
  return getAllSites(baseDir).map((site) => ({
    name: site.name,
    description: site.description,
    domain: site.domain,
    args: site.args,
    source: site.source,
    readOnly: site.readOnly,
  }));
}

export function readSiteScriptBody(filePath: string): string {
  const jsContent = readFileSync(filePath, "utf-8");
  return jsContent.replace(/\/\*\s*@meta[\s\S]*?\*\//, "").trim();
}

export function buildSiteEvalScript(filePath: string, argMap: Record<string, string>): string {
  const jsBody = readSiteScriptBody(filePath);
  const argsJson = JSON.stringify(argMap);
  return `(${jsBody})(${argsJson})`;
}

export function normalizeSiteArgs(args: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(args)) {
    if (value !== undefined && value !== null) {
      out[key] = String(value);
    }
  }
  return out;
}

export function validateSiteArgs(
  site: SiteMeta,
  argMap: Record<string, string>,
): { ok: true } | { ok: false; error: string; missing?: string; usage?: string; example?: string } {
  for (const [argName, argDef] of Object.entries(site.args)) {
    if (argDef.required && !argMap[argName]) {
      const usage = Object.keys(site.args)
        .map((name) => {
          const def = site.args[name];
          return def.required ? `<${name}>` : `[${name}]`;
        })
        .join(" ");
      return {
        ok: false,
        error: `missing required argument "${argName}"`,
        missing: argName,
        usage: `bun-browser site ${site.name} ${usage}`,
        example: site.example,
      };
    }
  }
  return { ok: true };
}
