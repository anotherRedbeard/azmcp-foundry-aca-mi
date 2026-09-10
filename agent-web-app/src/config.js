const requiredVariables = [
  "ENTRA_TENANT_ID",
  "ENTRA_SPA_CLIENT_ID",
  "ENTRA_API_SCOPE",
  "APIM_RESPONSES_URL",
  "APIM_SUBSCRIPTION_KEY",
];

export function loadConfig() {
  const missing = requiredVariables.filter((name) => !process.env[name]);

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  }

  const port = Number.parseInt(process.env.PORT ?? "3000", 10);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error("PORT must be an integer between 1 and 65535.");
  }

  const apimResponsesUrl = new URL(process.env.APIM_RESPONSES_URL);
  if (apimResponsesUrl.protocol !== "https:") {
    throw new Error("APIM_RESPONSES_URL must use HTTPS.");
  }

  const apiScopeParts = process.env.ENTRA_API_SCOPE.split("/");
  const scopeName = apiScopeParts.pop();
  const apiAudience = apiScopeParts.join("/");
  const apiClientId = apiAudience.startsWith("api://")
    ? apiAudience.slice("api://".length)
    : apiAudience;

  if (!scopeName || !apiAudience || !apiClientId) {
    throw new Error("ENTRA_API_SCOPE must be a complete delegated scope URI.");
  }

  return {
    port,
    isProduction: process.env.NODE_ENV === "production",
    entra: {
      tenantId: process.env.ENTRA_TENANT_ID,
      spaClientId: process.env.ENTRA_SPA_CLIENT_ID,
      apiScope: process.env.ENTRA_API_SCOPE,
      apiAudience,
      apiClientId,
      scopeName,
    },
    apim: {
      responsesUrl: apimResponsesUrl.toString(),
      subscriptionKey: process.env.APIM_SUBSCRIPTION_KEY,
    },
  };
}
