import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  server: { proxy: { "/api": "http://127.0.0.1:8799" } },
  build: { target: "es2022", assetsInlineLimit: 0, chunkSizeWarningLimit: 800 }
});
