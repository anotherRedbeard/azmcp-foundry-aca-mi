import { createRemoteJWKSet, jwtVerify } from "jose";

export function createTokenValidator(config) {
  const issuer = `https://login.microsoftonline.com/${config.entra.tenantId}/v2.0`;
  const jwks = createRemoteJWKSet(
    new URL(
      `https://login.microsoftonline.com/${config.entra.tenantId}/discovery/v2.0/keys`,
    ),
  );

  return async function validateToken(req, res, next) {
    const authorization = req.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return res.status(401).json({ error: "A bearer access token is required." });
    }

    try {
      const { payload } = await jwtVerify(authorization.slice("Bearer ".length), jwks, {
        issuer,
        audience: [config.entra.apiClientId, config.entra.apiAudience],
      });

      const scopes = typeof payload.scp === "string" ? payload.scp.split(" ") : [];
      if (!scopes.includes(config.entra.scopeName)) {
        return res.status(403).json({ error: "The required API scope is missing." });
      }

      if (payload.azp !== config.entra.spaClientId) {
        return res.status(403).json({ error: "The token was not issued to this SPA." });
      }

      return next();
    } catch (error) {
      console.warn(`Access token validation failed: ${error.code ?? error.name}`);
      return res.status(401).json({ error: "The access token is invalid or expired." });
    }
  };
}
