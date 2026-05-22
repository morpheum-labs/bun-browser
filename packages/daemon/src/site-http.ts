/**
 * HTTP handlers for /site/* — list, search, info, and run claw-bun-mcp adapters.
 *
 * Routes:
 *   GET  /site                  List adapters
 *   GET  /site/list             List adapters (alias)
 *   GET  /site/search?q=        Search adapters
 *   GET  /site/info?name=       Adapter metadata
 *   GET  /site/adapters/:name   Adapter metadata (path form, name may contain /)
 *   POST /site/run              Run adapter { name, args?, tabId? }
 *   POST /site/adapters/:name   Run adapter { args?, tabId? }
 */

import type { IncomingMessage, ServerResponse } from "node:http";
import {
  findSite,
  searchSites,
  siteInfoPayload,
  siteListPayload,
  runSiteAdapter,
  type Request,
  type Response,
  type SiteRunResult,
} from "@bun-browser/shared";

export type SiteCommandExecutor = (request: Request) => Promise<Response>;

interface SiteHttpOptions {
  executeCommand: SiteCommandExecutor;
}

export class SiteHttpHandler {
  private readonly executeCommand: SiteCommandExecutor;

  constructor(options: SiteHttpOptions) {
    this.executeCommand = options.executeCommand;
  }

  handle(req: IncomingMessage, res: ServerResponse, rawUrl: string): boolean {
    const parsed = new URL(rawUrl, "http://localhost");
    const pathname = parsed.pathname;

    if (!pathname.startsWith("/site")) return false;

    if (req.method === "GET") {
      if (pathname === "/site" || pathname === "/site/list") {
        this.sendJson(res, 200, { success: true, adapters: siteListPayload() });
        return true;
      }
      if (pathname === "/site/search") {
        const query = parsed.searchParams.get("q") ?? "";
        const matches = searchSites(query).map((site) => siteInfoPayload(site));
        this.sendJson(res, 200, { success: true, query, adapters: matches });
        return true;
      }
      if (pathname === "/site/info") {
        const name = parsed.searchParams.get("name");
        if (!name) {
          this.sendJson(res, 400, { success: false, error: 'Missing query parameter "name"' });
          return true;
        }
        this.handleInfo(res, name);
        return true;
      }
      if (pathname.startsWith("/site/adapters/")) {
        const name = decodeURIComponent(pathname.slice("/site/adapters/".length));
        if (!name) {
          this.sendJson(res, 400, { success: false, error: "Missing adapter name in path" });
          return true;
        }
        this.handleInfo(res, name);
        return true;
      }
      this.sendJson(res, 404, { success: false, error: "Not found" });
      return true;
    }

    if (req.method === "POST") {
      if (pathname === "/site/run") {
        void this.handleRunBody(req, res, null);
        return true;
      }
      if (pathname.startsWith("/site/adapters/")) {
        const name = decodeURIComponent(pathname.slice("/site/adapters/".length));
        if (!name) {
          this.sendJson(res, 400, { success: false, error: "Missing adapter name in path" });
          return true;
        }
        void this.handleRunBody(req, res, name);
        return true;
      }
      this.sendJson(res, 404, { success: false, error: "Not found" });
      return true;
    }

    this.sendJson(res, 405, { success: false, error: "Method not allowed" });
    return true;
  }

  private handleInfo(res: ServerResponse, name: string): void {
    const site = findSite(name);
    if (!site) {
      this.sendJson(res, 404, {
        success: false,
        error: `adapter "${name}" not found`,
        action: "GET /site/list",
      });
      return;
    }
    this.sendJson(res, 200, { success: true, adapter: siteInfoPayload(site) });
  }

  private async handleRunBody(
    req: IncomingMessage,
    res: ServerResponse,
    pathName: string | null,
  ): Promise<void> {
    try {
      const body = await this.readBody(req);
      const payload = JSON.parse(body) as {
        name?: string;
        args?: Record<string, unknown>;
        tabId?: number | string;
      };

      const name = pathName ?? payload.name;
      if (!name) {
        this.sendJson(res, 400, {
          success: false,
          error: 'Missing adapter name — use POST /site/run {"name":"platform/command"} or POST /site/adapters/platform/command',
        });
        return;
      }

      const site = findSite(name);
      if (!site) {
        this.sendJson(res, 404, {
          success: false,
          error: `adapter "${name}" not found`,
          action: "GET /site/list",
        });
        return;
      }

      const result = await runSiteAdapter(
        (request) => this.executeCommand(request),
        site,
        payload.args ?? {},
        { tabId: payload.tabId },
      );

      this.sendRunResult(res, result);
    } catch (error) {
      this.sendJson(res, 400, {
        success: false,
        error: error instanceof Error ? error.message : "Invalid request",
      });
    }
  }

  private sendRunResult(res: ServerResponse, result: SiteRunResult): void {
    if (result.success) {
      this.sendJson(res, 200, result);
      return;
    }
    this.sendJson(res, 422, result);
  }

  private readBody(req: IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      req.on("data", (chunk: Buffer) => chunks.push(chunk));
      req.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
      req.on("error", reject);
    });
  }

  private sendJson(res: ServerResponse, status: number, data: unknown): void {
    const body = JSON.stringify(data);
    res.writeHead(status, {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
    });
    res.end(body);
  }
}
