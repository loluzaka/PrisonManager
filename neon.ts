import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  // Declare your Neon services here
  preview: {
    realtime: true,
  },
  auth: false,
  functions: {
    hello: {
      name: "Prison Manager API",
      source: "./hello.ts",
      env: {
        PRISON_APP_API_KEY: {
          value: process.env.PRISON_APP_API_KEY,
          required: true,
        },
        PRISON_REALTIME_SECRET: {
          value: process.env.NEON_REALTIME_SECRET,
          required: true,
        },
      },
    },
  },
  buckets: {
    // "private" is the default; use "public_read" for anonymous reads
    uploads: { access: "private" },
  },
  // Branch policy: per-branch tuning
  branch: (branch) => {
    if (branch.isDefault) {
      // Default branch: no overrides, uses project defaults
      return {};
    }
    if (!branch.exists) {
      // New non-default branches: auto-expire
      // Run `neon checkout <name>` to create a new branch with these settings
      return { ttl: "7d" };
    }
    // Existing branch: no changes
    return {};
  },
});
