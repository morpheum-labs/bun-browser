import { readFileSync } from "node:fs";
import { defineConfig } from "tsup";

const packageJson = JSON.parse(
  readFileSync(new URL("./package.json", import.meta.url), "utf8"),
) as { version: string };

export default defineConfig({
  entry: {
    cli: "packages/cli/src/index.ts",
    daemon: "packages/daemon/src/index.ts",
    mcp: "packages/mcp/src/index.ts",
    provider: "bin/bun-browser-provider.ts",
  },
  format: ["esm"],
  dts: false,
  clean: true,
  sourcemap: true,
  target: "node18",
  splitting: true,
  outDir: "dist",
  banner: {
    js: "#!/usr/bin/env node",
  },
  define: {
    __BUN_BROWSER_VERSION__: JSON.stringify(packageJson.version),
  },
  noExternal: [/^(?!ws$).*/],
  external: ["ws"],
});
