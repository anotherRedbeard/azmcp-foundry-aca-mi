import path from "node:path";
import { fileURLToPath } from "node:url";
import "dotenv/config";
import express from "express";
import helmet from "helmet";
import { createTokenValidator } from "./auth.js";
import { loadConfig } from "./config.js";
import {
  buildResponseRequest,
  ResponseRequestValidationError,
} from "./response-request.js";

const config = loadConfig();
const app = express();
const publicDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "public",
);

function logMcpApprovalRequests(status, responseBody) {
  let response;
  try {
    response = JSON.parse(responseBody);
  } catch {
    return;
  }

  const output = Array.isArray(response.output) ? response.output : [];
  const approvals = output
    .filter((item) => item.type === "mcp_approval_request")
    .map((item) => ({
      id: item.id,
      server: item.server_label,
      tool: item.name,
      arguments: item.arguments,
    }));

  if (approvals.length > 0) {
    console.log(
      "MCP approval required:",
      JSON.stringify(
        {
          status,
          responseId: response.id,
          approvals,
        },
        null,
        2,
      ),
    );
  }
}

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
  let requestBody;
  try {
    requestBody = buildResponseRequest(req.body);
  } catch (error) {
    if (error instanceof ResponseRequestValidationError) {
      return res.status(400).json({ error: error.message });
    }
    throw error;
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
  logMcpApprovalRequests(upstream.status, responseBody);
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
