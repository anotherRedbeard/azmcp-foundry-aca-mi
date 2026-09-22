import { PublicClientApplication } from "@azure/msal-browser";

const signedOut = document.querySelector("#signed-out");
const chatPanel = document.querySelector("#chat-panel");
const accountActions = document.querySelector("#account-actions");
const signInButton = document.querySelector("#sign-in-button");
const messages = document.querySelector("#messages");
const messageList = document.querySelector(".message-list");
const form = document.querySelector("#chat-form");
const input = document.querySelector("#message");
const sendButton = document.querySelector("#send-button");
const formStatus = document.querySelector("#form-status");

let authClient;
let account;
let apiScope;
let previousResponseId;
let oauthConsentPending = false;

async function callAgent(agentInput, responseId = previousResponseId) {
  const token = await acquireApiToken();
  const body = {
    input: agentInput,
  };

  if (responseId) {
    body.previous_response_id = responseId;
  }

  const response = await fetch("/api/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorBody = await response.json().catch(() => ({}));
    const message =
      typeof errorBody.error === "string"
        ? errorBody.error
        : errorBody.error?.message;
    throw new Error(message || `Request failed with status ${response.status}.`);
  }

  return response.json();
}

async function acquireApiToken() {
  try {
    const result = await authClient.acquireTokenSilent({
      account,
      scopes: [apiScope],
    });
    return result.accessToken;
  } catch {
    await authClient.acquireTokenRedirect({
      account,
      scopes: [apiScope],
    });
    throw new Error("Redirecting to Microsoft Entra ID.");
  }
}

function addMessage(role, text) {
  const article = document.createElement("article");
  article.className = `message ${role}`;

  const avatar = document.createElement("div");
  avatar.className = "avatar";
  avatar.textContent = role === "user" ? "Y" : "A";

  const bubble = document.createElement("div");
  bubble.className = "bubble";

  const label = document.createElement("p");
  label.className = "message-label";
  label.textContent = role === "user" ? "You" : "Agent";

  const content = document.createElement("p");
  content.textContent = text;

  bubble.append(label, content);
  article.append(avatar, bubble);
  messageList.append(article);
  scrollMessagesToBottom();
}

function formatArguments(value) {
  if (typeof value !== "string") {
    return JSON.stringify(value ?? {}, null, 2);
  }

  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}

function requestMcpApproval(request) {
  return new Promise((resolve) => {
    const article = document.createElement("article");
    article.className = "message approval";

    const avatar = document.createElement("div");
    avatar.className = "avatar";
    avatar.textContent = "!";

    const bubble = document.createElement("div");
    bubble.className = "bubble approval-card";

    const label = document.createElement("p");
    label.className = "message-label";
    label.textContent = "Approval required";

    const title = document.createElement("p");
    title.className = "approval-title";
    title.textContent = `Allow ${request.name || "this MCP tool"} to run?`;

    const server = document.createElement("p");
    server.className = "approval-server";
    server.textContent = `Server: ${request.server_label || "Unknown"}`;

    const argumentsLabel = document.createElement("p");
    argumentsLabel.className = "approval-arguments-label";
    argumentsLabel.textContent = "Arguments";

    const argumentsBlock = document.createElement("pre");
    argumentsBlock.className = "approval-arguments";
    argumentsBlock.textContent = formatArguments(request.arguments);

    const actions = document.createElement("div");
    actions.className = "approval-actions";

    const rejectButton = document.createElement("button");
    rejectButton.className = "button";
    rejectButton.type = "button";
    rejectButton.textContent = "Reject";

    const approveButton = document.createElement("button");
    approveButton.className = "button primary";
    approveButton.type = "button";
    approveButton.textContent = "Approve";

    const complete = (approved) => {
      rejectButton.disabled = true;
      approveButton.disabled = true;
      bubble.classList.add(approved ? "approved" : "rejected");
      label.textContent = approved ? "Approved" : "Rejected";
      resolve(approved);
    };

    rejectButton.addEventListener("click", () => complete(false), { once: true });
    approveButton.addEventListener("click", () => complete(true), { once: true });

    actions.append(rejectButton, approveButton);
    bubble.append(
      label,
      title,
      server,
      argumentsLabel,
      argumentsBlock,
      actions,
    );
    article.append(avatar, bubble);
    messageList.append(article);
    scrollMessagesToBottom();
  });
}

function getOAuthConsentRequest(response) {
  return (response.output ?? []).find(
    (item) =>
      item.type === "oauth_consent_request" &&
      typeof item.consent_link === "string",
  );
}

function addOAuthConsentMessage(consentRequest, originalMessage) {
  const consentUrl = new URL(consentRequest.consent_link);
  if (consentUrl.protocol !== "https:") {
    throw new Error("The agent returned an invalid OAuth consent URL.");
  }

  oauthConsentPending = true;

  const article = document.createElement("article");
  article.className = "message assistant";

  const avatar = document.createElement("div");
  avatar.className = "avatar";
  avatar.textContent = "A";

  const bubble = document.createElement("div");
  bubble.className = "bubble";

  const label = document.createElement("p");
  label.className = "message-label";
  label.textContent = "Authorization required";

  const content = document.createElement("p");
  content.textContent =
    "Authorize the MCP connection with the Azure account whose permissions you want the agent to use.";

  const actions = document.createElement("div");
  actions.className = "consent-actions";

  const authorizeLink = document.createElement("a");
  authorizeLink.className = "button primary";
  authorizeLink.href = consentUrl.href;
  authorizeLink.target = "_blank";
  authorizeLink.rel = "noopener noreferrer";
  authorizeLink.textContent = "Authorize access";

  const continueButton = document.createElement("button");
  continueButton.className = "button";
  continueButton.type = "button";
  continueButton.textContent = "Continue after authorization";
  continueButton.addEventListener("click", async () => {
    continueButton.disabled = true;
    formStatus.textContent = "Continuing the request...";
    formStatus.className = "form-status";

    try {
      const result = await callAgent(originalMessage);
      await processAgentResponse(result, originalMessage);
      formStatus.textContent = "";
      if (!oauthConsentPending) {
        input.disabled = false;
        sendButton.disabled = false;
        input.focus();
      }
    } catch (error) {
      formStatus.textContent = error.message;
      formStatus.className = "form-status error";
      continueButton.disabled = false;
    }
  });

  actions.append(authorizeLink, continueButton);
  bubble.append(label, content, actions);
  article.append(avatar, bubble);
  messageList.append(article);
  scrollMessagesToBottom();
}

function scrollMessagesToBottom(behavior = "smooth") {
  requestAnimationFrame(() => {
    messages.scrollTo({
      top: messages.scrollHeight,
      behavior,
    });
  });
}

function extractResponseText(response) {
  if (typeof response.output_text === "string" && response.output_text) {
    return response.output_text;
  }

  const textParts = (response.output ?? [])
    .filter((item) => item.type === "message")
    .flatMap((item) => item.content ?? [])
    .filter((content) => content.type === "output_text")
    .map((content) => content.text)
    .filter(Boolean);

  return textParts.join("\n");
}

function getMcpApprovalRequests(response) {
  return (response.output ?? []).filter(
    (item) =>
      item.type === "mcp_approval_request" &&
      typeof item.id === "string" &&
      item.id.length > 0,
  );
}

async function processAgentResponse(initialResponse, originalMessage) {
  let response = initialResponse;

  for (let round = 0; round < 10; round += 1) {
    previousResponseId = response.id;

    const consentRequest = getOAuthConsentRequest(response);
    if (consentRequest) {
      addOAuthConsentMessage(consentRequest, originalMessage);
      return;
    }

    oauthConsentPending = false;
    const responseText = extractResponseText(response);
    if (responseText) {
      addMessage("assistant", responseText);
    }

    const approvalRequests = getMcpApprovalRequests(response);
    if (approvalRequests.length === 0) {
      if (!responseText) {
        throw new Error(
          `The agent returned no text. Response status: ${response.status ?? "unknown"}.`,
        );
      }
      return;
    }

    formStatus.textContent = `Review ${approvalRequests.length} MCP tool approval request${approvalRequests.length === 1 ? "" : "s"}.`;
    const decisions = await Promise.all(
      approvalRequests.map((request) => requestMcpApproval(request)),
    );

    formStatus.textContent = "The agent is continuing...";
    response = await callAgent(
      approvalRequests.map((request, index) => ({
        type: "mcp_approval_response",
        approval_request_id: request.id,
        approve: decisions[index],
      })),
      response.id,
    );
  }

  throw new Error("The agent requested too many consecutive approval rounds.");
}

function resetConversation() {
  previousResponseId = undefined;
  oauthConsentPending = false;
  messageList.replaceChildren();
  addMessage("assistant", "A new conversation is ready. What would you like to know?");
  formStatus.textContent = "";
  formStatus.className = "form-status";
  input.disabled = false;
  sendButton.disabled = false;
  input.focus();
}

function showAuthenticatedView() {
  signedOut.hidden = true;
  chatPanel.hidden = false;

  const username = document.createElement("span");
  username.textContent = account.name || account.username;

  const resetButton = document.createElement("button");
  resetButton.className = "button";
  resetButton.type = "button";
  resetButton.textContent = "New chat";
  resetButton.addEventListener("click", resetConversation);

  const logout = document.createElement("button");
  logout.className = "button";
  logout.type = "button";
  logout.textContent = "Sign out";
  logout.addEventListener("click", () => {
    authClient.logoutRedirect({
      account,
      postLogoutRedirectUri: window.location.origin,
    });
  });

  accountActions.replaceChildren(username, resetButton, logout);
  scrollMessagesToBottom("auto");
  input.focus();
}

async function initializeAuthentication() {
  const configResponse = await fetch("/api/config");
  if (!configResponse.ok) {
    throw new Error("Unable to load the authentication configuration.");
  }

  const config = await configResponse.json();
  apiScope = config.apiScope;
  authClient = new PublicClientApplication({
    auth: {
      clientId: config.spaClientId,
      authority: `https://login.microsoftonline.com/${config.tenantId}`,
      redirectUri: window.location.origin,
      postLogoutRedirectUri: window.location.origin,
    },
    cache: {
      cacheLocation: "sessionStorage",
    },
  });

  await authClient.initialize();
  const redirectResult = await authClient.handleRedirectPromise();
  account = redirectResult?.account || authClient.getAllAccounts()[0];

  if (account) {
    authClient.setActiveAccount(account);
    showAuthenticatedView();
  } else {
    signedOut.hidden = false;
    chatPanel.hidden = true;
  }
}

signInButton.addEventListener("click", () => {
  authClient.loginRedirect({
    scopes: [apiScope],
  });
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = input.value.trim();
  if (!message) {
    return;
  }

  addMessage("user", message);
  input.value = "";
  input.disabled = true;
  sendButton.disabled = true;
  formStatus.textContent = "The agent is working...";
  formStatus.className = "form-status";

  try {
    const result = await callAgent(message);
    await processAgentResponse(result, message);
    formStatus.textContent = "";
  } catch (error) {
    addMessage("assistant", "I could not complete that request.");
    formStatus.textContent = error.message;
    formStatus.className = "form-status error";
  } finally {
    if (!oauthConsentPending) {
      input.disabled = false;
      sendButton.disabled = false;
      input.focus();
    }
  }
});

input.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    form.requestSubmit();
  }
});

window.addEventListener("resize", () => scrollMessagesToBottom("auto"));

initializeAuthentication().catch((error) => {
  signedOut.hidden = false;
  chatPanel.hidden = true;
  accountActions.textContent = error.message;
});
