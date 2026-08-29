import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          HOST_RECONNECT_TIMEOUT_SECONDS: "5",
        },
      },
    }),
  ],
  test: {
    testTimeout: 12_000,
  },
});
