import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/main.ts", "src/index.ts"],
  format: ["esm"],
  target: "es2022",
  platform: "node",
  external: ["bun:ffi"],
  dts: true,
  sourcemap: true,
  clean: true,
  splitting: false,
  banner: {
    js: "#!/usr/bin/env bun",
  },
});
