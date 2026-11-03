import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  server: {
    host: "0.0.0.0",
    port: 3000,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp"
    },
    proxy: {
      "/hvsc": {
        target: "https://hvsc.brona.dk/HVSC/C64Music",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/hvsc/, "")
      }
    }
  },
  preview: {
    host: "0.0.0.0",
    port: 3000,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp"
    },
    proxy: {
      "/hvsc": {
        target: "https://hvsc.brona.dk/HVSC/C64Music",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/hvsc/, "")
      }
    }
  }
});
