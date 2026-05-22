/**
 * Community site adapters install path (~/.bun-browser/claw-bun-mcp).
 */

import { existsSync, renameSync } from "node:fs";
import { join } from "node:path";
import {
  COMMUNITY_SITES_DIR_NAME,
  LEGACY_COMMUNITY_SITES_DIR_NAME,
} from "./constants.js";
import { DAEMON_DIR } from "./daemon-client.js";

/** Resolve community adapters dir, migrating legacy bb-sites → claw-bun-mcp. */
export function resolveCommunitySitesDir(baseDir: string = DAEMON_DIR): string {
  const dir = join(baseDir, COMMUNITY_SITES_DIR_NAME);
  const legacy = join(baseDir, LEGACY_COMMUNITY_SITES_DIR_NAME);
  if (!existsSync(dir) && existsSync(legacy)) {
    renameSync(legacy, dir);
  }
  return dir;
}
