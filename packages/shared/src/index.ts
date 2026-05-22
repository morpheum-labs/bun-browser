/**
 * @bun-browser/shared
 * 共享类型和工具函数
 */

export {
  type ActionType,
  type ConsoleMessageInfo,
  type DaemonStatus,
  type JSErrorInfo,
  type NetworkRequestInfo,
  type RefInfo,
  type Request,
  type Response,
  type ResponseData,
  type SnapshotData,
  type TabInfo,
  type TraceEvent,
  type TraceStatus,
  generateId,
} from "./protocol.js";

export {
  COMMAND_TIMEOUT,
  COMMUNITY_SITES_DIR_NAME,
  DAEMON_HOST,
  DAEMON_PORT,
  DEFAULT_COMMUNITY_SITES_GH_REPO,
  DEFAULT_COMMUNITY_SITES_REPO,
  LEGACY_COMMUNITY_SITES_DIR_NAME,
  SSE_HEARTBEAT_INTERVAL,
  SSE_MAX_RECONNECT_ATTEMPTS,
  SSE_RECONNECT_DELAY,
} from "./constants.js";

export { resolveCommunitySitesDir } from "./community-sites-path.js";

export {
  type CommandDef,
  COMMANDS,
  findCommand,
  getCommandsByCategory,
} from "./commands.js";

export {
  type DaemonInfo,
  DAEMON_DIR,
  DAEMON_JSON,
  readDaemonJson,
  isProcessAlive,
  httpJson,
} from "./daemon-client.js";
