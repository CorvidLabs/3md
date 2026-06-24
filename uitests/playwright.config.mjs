import { defineConfig, devices } from "@playwright/test";

// Serves the static demos in web/ and runs the lab tests against the two
// engines that matter: Chromium (Chrome/Edge/Arc) and WebKit (Safari). The
// WebKit project is what guards against the Safari-only 3D depth regressions
// that z-index masks in Chromium.
const PORT = 8232;

export default defineConfig({
  testDir: ".",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  // The tab/gallery loops scrub many examples in sequence; give them headroom
  // on slower CI machines (the default 30s is exceeded there).
  timeout: 90_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: `http://localhost:${PORT}`,
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
  webServer: {
    command: `python3 -m http.server ${PORT} --directory ../web`,
    port: PORT,
    reuseExistingServer: !process.env.CI,
    stdout: "ignore",
    stderr: "pipe",
  },
});
