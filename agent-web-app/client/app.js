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

async function callAgent(message) {
  const token = await acquireApiToken();
  const body = {
    input: message,
  };

  if (previousResponseId) {
    body.previous_response_id = previousResponseId;
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

  if (textParts.length === 0) {
    throw new Error(`The agent returned no text. Response status: ${response.status ?? "unknown"}.`);
  }

  return textParts.join("\n");
}

function resetConversation() {
  previousResponseId = undefined;
  messageList.replaceChildren();
  addMessage("assistant", "A new conversation is ready. What would you like to know?");
  formStatus.textContent = "";
  formStatus.className = "form-status";
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
    previousResponseId = result.id;
    addMessage("assistant", extractResponseText(result));
    formStatus.textContent = "";
  } catch (error) {
    addMessage("assistant", "I could not complete that request.");
    formStatus.textContent = error.message;
    formStatus.className = "form-status error";
  } finally {
    input.disabled = false;
    sendButton.disabled = false;
    input.focus();
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
