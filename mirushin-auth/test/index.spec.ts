import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

const baseEnv = {
  SHIKIMORI_CLIENT_ID: "shiki-client",
  SHIKIMORI_CLIENT_SECRET: "shiki-secret",
  SHIKIMORI_REDIRECT_URI: "https://auth.emp0ry.com/callback",
  SHIKIMORI_USER_AGENT: "MiruShin",
  MAL_CLIENT_ID_DESKTOP: "mal-desktop",
  MAL_CLIENT_ID_MOBILE: "mal-mobile",
};

async function fetchWorker(path: string, init?: RequestInit) {
  const request = new IncomingRequest(`https://auth.emp0ry.com${path}`, init);
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, baseEnv, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

describe("mirushin-auth worker", () => {
  it("renders a callback error instead of throwing when no code is present", async () => {
    const response = await fetchWorker("/callback");

    expect(response.status).toBe(400);
    expect(await response.text()).toContain("No authorization code received.");
  });

  it("redirects default Shikimori authorization through the Worker", async () => {
    const response = await fetchWorker("/shikimori/authorize?state=shikimori", {
      redirect: "manual",
    });

    expect(response.status).toBe(302);
    const location = new URL(response.headers.get("location") ?? "");
    expect(location.origin).toBe("https://shikimori.io");
    expect(location.pathname).toBe("/oauth/authorize");
    expect(location.searchParams.get("client_id")).toBe("shiki-client");
    expect(location.searchParams.get("redirect_uri")).toBe(
      "https://auth.emp0ry.com/callback",
    );
  });

  it("redirects MAL authorization with the platform-specific client id", async () => {
    const response = await fetchWorker(
      "/mal/authorize?platform=mobile&code_challenge=verifier&state=mal",
      { redirect: "manual" },
    );

    expect(response.status).toBe(302);
    const location = new URL(response.headers.get("location") ?? "");
    expect(location.origin).toBe("https://myanimelist.net");
    expect(location.pathname).toBe("/v1/oauth2/authorize");
    expect(location.searchParams.get("client_id")).toBe("mal-mobile");
    expect(location.searchParams.get("redirect_uri")).toBe("app://mirushin/auth");
  });
});
