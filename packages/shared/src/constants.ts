/**
 * bun-browser 共享常量
 */

/** Daemon HTTP 服务端口 */
export const DAEMON_PORT = 19824;

/** Daemon 主机地址 */
export const DAEMON_HOST = "127.0.0.1";

/** SSE 心跳间隔（毫秒） - 15秒确保 MV3 Service Worker 不休眠 */
export const SSE_HEARTBEAT_INTERVAL = 15000; // 15 秒

/** 命令执行超时时间（毫秒） */
export const COMMAND_TIMEOUT = 30000; // 30 秒

/** SSE 重连延迟（毫秒） */
export const SSE_RECONNECT_DELAY = 3000; // 3 秒

/** SSE 最大重连尝试次数 */
export const SSE_MAX_RECONNECT_ATTEMPTS = 5;

/** Subdir under ~/.bun-browser/ for community site adapters (cloned from claw-bun-mcp) */
export const COMMUNITY_SITES_DIR_NAME = "claw-bun-mcp";

/** Legacy subdir name (auto-migrated to COMMUNITY_SITES_DIR_NAME) */
export const LEGACY_COMMUNITY_SITES_DIR_NAME = "bb-sites";

/** Default community site adapter git repo (cloned to ~/.bun-browser/claw-bun-mcp) */
export const DEFAULT_COMMUNITY_SITES_REPO = "https://github.com/clawhubmx/claw-bun-mcp.git";

/** GitHub repo slug for adapter issues/PRs (owner/name) */
export const DEFAULT_COMMUNITY_SITES_GH_REPO = "clawhubmx/claw-bun-mcp";
