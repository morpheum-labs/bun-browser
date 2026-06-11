/**
 * Run a site adapter via daemon dispatch (eval in matching browser tab).
 */

import { generateId, type Request, type Response, type TabInfo } from "./protocol.js";
import {
  buildSiteEvalScript,
  findSite,
  normalizeSiteArgs,
  validateSiteArgs,
  type SiteMeta,
} from "./site-registry.js";

export type SiteDispatch = (request: Request) => Promise<Response>;

export interface SiteRunOptions {
  tabId?: number | string;
  /** Wait after opening a new tab for the domain (ms). */
  tabOpenWaitMs?: number;
}

export interface SiteRunSuccess {
  success: true;
  id: string;
  data: unknown;
  tab?: number | string;
  seq?: number;
}

export interface SiteRunFailure {
  success: false;
  id: string;
  error: string;
  hint?: string;
  tab?: number | string;
}

export type SiteRunResult = SiteRunSuccess | SiteRunFailure;

function matchTabOrigin(tabUrl: string, domain: string): boolean {
  try {
    const hostname = new URL(tabUrl).hostname;
    return hostname === domain || hostname.endsWith("." + domain);
  } catch {
    return false;
  }
}

const NOTION_BUSY_PROBE_SCRIPT = `(async function() {
  function hasCookie(name) {
    return document.cookie.split(';').some(function(c) {
      return c.trim().startsWith(name + '=');
    });
  }
  if (!hasCookie('notion_user_id') || !hasCookie('notion_users')) {
    return { busy: false, loggedIn: false, url: location.href };
  }
  var h = globalThis.__notionAiChatHelpers;
  if (h && h.isChatInProgress) {
    return {
      busy: h.isChatInProgress(),
      generating: h.isGenerating ? h.isGenerating() : false,
      conversationId: h.getConversationId ? h.getConversationId() : null,
      loggedIn: true,
      helpersLoaded: true,
      url: location.href
    };
  }
  var text = (document.body && (document.body.innerText || document.body.textContent) || '').slice(-12000);
  if (/Notion AI finished/i.test(text)) {
    return { busy: false, loggedIn: true, helpersLoaded: false, url: location.href };
  }
  var busy = /exploring|computing|thought|thinking|searching|reading files|running tool|generating|writing file|loading web page|loaded web page|called function|searched the web|browsing|fetch(?:ing)? (?:top|recent)/i.test(text);
  return { busy: busy, loggedIn: true, helpersLoaded: false, url: location.href };
})()`;

function domainOpenUrl(domain: string): string {
  if (domain === "app.notion.com") return `https://${domain}/ai`;
  return `https://${domain}`;
}

async function probeNotionTabBusy(
  dispatch: SiteDispatch,
  tabId: number | string,
): Promise<boolean> {
  const probe = findSite("notion/tab-probe");
  const script = probe ? buildSiteEvalScript(probe.filePath, {}) : NOTION_BUSY_PROBE_SCRIPT;
  const resp = await dispatch({
    id: generateId(),
    action: "eval",
    script,
    tabId,
  });
  if (!resp.success) return true;
  const parsed = parseAdapterResult(resp.data?.result);
  if (typeof parsed === "object" && parsed !== null && "busy" in parsed) {
    return !!(parsed as { busy: boolean }).busy;
  }
  return false;
}

async function openDomainTab(
  dispatch: SiteDispatch,
  domain: string,
  tabOpenWaitMs: number,
): Promise<number | string | undefined> {
  const newResp = await dispatch({
    id: generateId(),
    action: "tab_new",
    url: domainOpenUrl(domain),
  });
  if (!newResp.success) {
    throw new Error(newResp.error || "tab_new failed");
  }

  if (tabOpenWaitMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, tabOpenWaitMs));
  }

  return newResp.data?.tabId;
}

async function resolveAutoSiteTabId(
  dispatch: SiteDispatch,
  site: SiteMeta,
  tabOpenWaitMs: number,
): Promise<number | string | undefined> {
  if (!site.domain) return undefined;

  const listResp = await dispatch({ id: generateId(), action: "tab_list" });
  const matchingTabs =
    listResp.success && listResp.data?.tabs
      ? listResp.data.tabs.filter((tab: TabInfo) => matchTabOrigin(tab.url, site.domain))
      : [];

  if (site.domain === "app.notion.com") {
    for (const tab of matchingTabs) {
      const busy = await probeNotionTabBusy(dispatch, tab.tabId);
      if (!busy) return tab.tabId;
    }
    return openDomainTab(dispatch, site.domain, tabOpenWaitMs);
  }

  if (matchingTabs.length > 0) return matchingTabs[0].tabId;
  return openDomainTab(dispatch, site.domain, tabOpenWaitMs);
}

export async function resolveSiteTabId(
  dispatch: SiteDispatch,
  site: SiteMeta,
  tabId?: number | string,
  tabOpenWaitMs = 3000,
): Promise<number | string | undefined> {
  if (tabId === "auto") {
    return resolveAutoSiteTabId(dispatch, site, tabOpenWaitMs);
  }
  if (tabId !== undefined) return tabId;
  if (!site.domain) return undefined;

  const listResp = await dispatch({ id: generateId(), action: "tab_list" });
  if (listResp.success && listResp.data?.tabs) {
    const matchingTab = listResp.data.tabs.find((tab: TabInfo) =>
      matchTabOrigin(tab.url, site.domain),
    );
    if (matchingTab) return matchingTab.tabId;
  }

  return openDomainTab(dispatch, site.domain, tabOpenWaitMs);
}

function parseAdapterResult(result: unknown): unknown {
  if (result === undefined || result === null) return null;
  if (typeof result === "string") {
    try {
      return JSON.parse(result);
    } catch {
      return result;
    }
  }
  return result;
}

function authHint(site: SiteMeta, hint?: string): string | undefined {
  const checkText = hint || "";
  const isAuthError = /401|403|unauthorized|forbidden|not.?logged|login.?required|sign.?in|auth/i.test(
    checkText,
  );
  if (isAuthError && site.domain) {
    return `Please log in to https://${site.domain} in your browser first, then retry.`;
  }
  return hint;
}

export async function runSiteAdapter(
  dispatch: SiteDispatch,
  site: SiteMeta,
  rawArgs: Record<string, unknown>,
  options: SiteRunOptions = {},
): Promise<SiteRunResult> {
  const argMap = normalizeSiteArgs(rawArgs);
  const validation = validateSiteArgs(site, argMap);
  if (!validation.ok) {
    return {
      success: false,
      id: generateId(),
      error: validation.error,
      hint: validation.example ? `Example: ${validation.example}` : validation.usage,
    };
  }

  let targetTabId: number | string | undefined;
  try {
    targetTabId = await resolveSiteTabId(
      dispatch,
      site,
      options.tabId,
      options.tabOpenWaitMs,
    );
  } catch (error) {
    return {
      success: false,
      id: generateId(),
      error: error instanceof Error ? error.message : "Failed to resolve tab",
      hint: site.domain
        ? `Open https://${site.domain} in your browser, make sure you are logged in, then retry.`
        : undefined,
    };
  }

  const script = buildSiteEvalScript(site.filePath, argMap);
  const evalId = generateId();
  const evalResp = await dispatch({
    id: evalId,
    action: "eval",
    script,
    tabId: targetTabId,
  });

  if (!evalResp.success) {
    return {
      success: false,
      id: evalId,
      error: evalResp.error || "eval failed",
      hint: site.domain
        ? `Open https://${site.domain} in your browser, make sure you are logged in, then retry.`
        : undefined,
      tab: targetTabId,
    };
  }

  const parsed = parseAdapterResult(evalResp.data?.result);
  if (typeof parsed === "object" && parsed !== null && "error" in parsed) {
    const errObj = parsed as { error: string; hint?: string };
    return {
      success: false,
      id: evalId,
      error: errObj.error,
      hint: authHint(site, errObj.hint) || errObj.hint,
      tab: targetTabId,
    };
  }

  return {
    success: true,
    id: evalId,
    data: parsed,
    tab: targetTabId,
    seq: evalResp.data?.seq,
  };
}
