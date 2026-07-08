import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://jtrefon.github.io/ai-ide/",
  base: "/ai-ide",
  outDir: "../site",
  publicDir: "public",
  integrations: [sitemap()],
  trailingSlash: "ignore",
});
