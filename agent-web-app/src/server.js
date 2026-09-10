import path from "node:path";
import { fileURLToPath } from "node:url";
import "dotenv/config";
import express from "express";
import helmet from "helmet";
import { createTokenValidator } from "./auth.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const app = express();
const publicDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "public",
);

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        "script-src": ["'self'", "'unsafe-inline'"],
        "connect-src": [
          "'self'",
          "https://login.microsoftonline.com",
        ],
        "frame-src": ["https://login.microsoftonline.com"],
      },
    },
  }),
);
app.use(express.json({ limit: "32kb" }));
app.use(express.static(publicDirectory));

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/api/config", (_req, res) => {
  res.json({
    tenantId: config.entra.tenantId,
    spaClientId: config.entra.spaClientId,
    apiScope: config.entra.apiScope,
  });
});

app.post("/api/responses", createTokenValidator(config), async (req, res) => {
  const input = req.body?.input;
  const previousResponseId = req.body?.previous_response_id;

  if (typeof input !== "string" || input.trim().length === 0) {
    return res.status(400).json({ error: "A non-empty input string is required." });
  }

  if (
    previousResponseId !== undefined &&
    typeof previousResponseId !== "string"
  ) {
    return res.status(400).json({ error: "previous_response_id must be a string." });
  }

  const requestBody = { input: input.trim() };
  if (previousResponseId) {
    requestBody.previous_response_id = previousResponseId;
  }

  const upstream = await fetch(config.apim.responsesUrl, {
    method: "POST",
    headers: {
      Authorization: req.get("Authorization"),
      "Content-Type": "application/json",
      "Ocp-Apim-Subscription-Key": config.apim.subscriptionKey,
    },
    body: JSON.stringify(requestBody),
    signal: AbortSignal.timeout(120_000),
  });

  const responseBody = await upstream.text();
  const contentType = upstream.headers.get("content-type");
  if (contentType) {
    res.type(contentType);
  }

  return res.status(upstream.status).send(responseBody);
});

app.use((error, req, res, _next) => {
  console.error(error);

  if (req.path.startsWith("/api/")) {
    return res.status(500).json({
      error: "The request could not be completed. Check the server logs for details.",
    });
  }

  return res.status(500).send("The request could not be completed.");
});

app.listen(config.port, () => {
  console.log(`Foundry Agent Web App listening on http://localhost:${config.port}`);
});
