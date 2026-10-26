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
const conversationList = document.querySelector("#conversation-list");
const historyEmpty = document.querySelector("#history-empty");
const historyCount = document.querySelector("#history-count");
const newChatButton = document.querySelector("#new-chat-button");
const clearHistoryButton = document.querySelector("#clear-history-button");

let authClient;
let account;
let apiScope;
let previousResponseId;
let activeConversationId;
let conversations = [];
let oauthConsentPending = false;
let requestInProgress = false;

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

async function authenticatedFetch(path, options = {}) {
  const token = await acquireApiToken();
  const response = await fetch(path, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...options.headers,
    },
  });

  if (!response.ok) {
    const errorBody = await response.json().catch(() => ({}));
    const message =
      typeof errorBody.error === "string"
        ? errorBody.error
        : errorBody.error?.message;
    throw new Error(message || `Request failed with status ${response.status}.`);
  }

  return response.status === 204 ? undefined : response.json();
}

async function callAgent(agentInput, responseId = previousResponseId) {
  const body = { input: agentInput };
  if (responseId) {
    body.previous_response_id = responseId;
  }

  return authenticatedFetch("/api/responses", {
    method: "POST",
    body: JSON.stringify(body),
  });
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

function showConversationPrompt(text) {
  messageList.replaceChildren();
  addMessage("assistant", text);
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
        setInteractionDisabled(false);
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

  return (response.output ?? [])
    .filter((item) => item.type === "message")
    .flatMap((item) => item.content ?? [])
    .filter((content) => content.type === "output_text")
    .map((content) => content.text)
    .filter(Boolean)
    .join("\n");
}

function getMcpApprovalRequests(response) {
  return (response.output ?? []).filter(
    (item) =>
      item.type === "mcp_approval_request" &&
      typeof item.id === "string" &&
      item.id.length > 0,
  );
}

function createConversationTitle(message) {
  const oneLine = message.replace(/\s+/g, " ").trim();
  return oneLine.length > 72 ? `${oneLine.slice(0, 71)}...` : oneLine;
}

function formatConversationDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  const now = new Date();
  if (date.toDateString() === now.toDateString()) {
    return date.toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
    });
  }

  return date.toLocaleDateString([], {
    month: "short",
    day: "numeric",
  });
}

function closeConversationMenus(exceptConversationId) {
  for (const menu of conversationList.querySelectorAll(".conversation-menu")) {
    const keepOpen =
      menu.closest(".conversation-item")?.dataset.conversationId ===
      exceptConversationId;
    menu.hidden = !keepOpen;
    menu.previousElementSibling?.setAttribute(
      "aria-expanded",
      keepOpen ? "true" : "false",
    );
  }
}

function renderConversationList() {
  const items = conversations.map((conversation) => {
    const item = document.createElement("div");
    item.className = "conversation-item";
    item.dataset.conversationId = conversation.id;
    item.classList.toggle("active", conversation.id === activeConversationId);

    const openButton = document.createElement("button");
    openButton.className = "conversation-open";
    openButton.type = "button";
    openButton.disabled = requestInProgress;
    openButton.setAttribute(
      "aria-label",
      `Open conversation: ${conversation.title}`,
    );

    const title = document.createElement("span");
    title.className = "conversation-title";
    title.textContent = conversation.title;

    const date = document.createElement("span");
    date.className = "conversation-date";
    date.textContent = formatConversationDate(conversation.updatedAt);
    openButton.append(title, date);

    const menuWrap = document.createElement("div");
    menuWrap.className = "conversation-menu-wrap";

    const menuButton = document.createElement("button");
    menuButton.className = "conversation-menu-button";
    menuButton.type = "button";
    menuButton.disabled = requestInProgress;
    menuButton.textContent = "...";
    menuButton.setAttribute("aria-label", `Actions for ${conversation.title}`);
    menuButton.setAttribute("aria-expanded", "false");

    const menu = document.createElement("div");
    menu.className = "conversation-menu";
    menu.hidden = true;

    const renameButton = document.createElement("button");
    renameButton.className = "conversation-rename";
    renameButton.type = "button";
    renameButton.textContent = "Rename chat";

    const deleteButton = document.createElement("button");
    deleteButton.className = "conversation-delete";
    deleteButton.type = "button";
    deleteButton.textContent = "Delete chat";
    menu.append(renameButton, deleteButton);
    menuWrap.append(menuButton, menu);
    item.append(openButton, menuWrap);
    return item;
  });

  conversationList.replaceChildren(...items);
  historyEmpty.hidden = conversations.length > 0;
  historyCount.textContent = String(conversations.length);
  clearHistoryButton.disabled =
    requestInProgress || conversations.length === 0;
}

async function refreshConversationList() {
  conversations = await authenticatedFetch("/api/conversations");
  renderConversationList();
}

async function openConversation(conversationId) {
  const conversation = await authenticatedFetch(
    `/api/conversations/${encodeURIComponent(conversationId)}`,
  );
  activeConversationId = conversation.id;
  previousResponseId = conversation.previousResponseId || undefined;
  oauthConsentPending = false;
  messageList.replaceChildren();

  if (conversation.messages.length === 0) {
    addMessage("assistant", "This conversation is ready.");
  } else {
    for (const message of conversation.messages) {
      addMessage(message.role, message.content);
    }
  }

  renderConversationList();
  formStatus.textContent = "";
  formStatus.className = "form-status";
  scrollMessagesToBottom("auto");
}

async function initializeHistory() {
  await refreshConversationList();
  if (conversations.length > 0) {
    await openConversation(conversations[0].id);
  } else {
    resetConversation();
  }
}

async function ensureConversation(firstMessage) {
  if (activeConversationId) {
    return activeConversationId;
  }

  const conversation = await authenticatedFetch("/api/conversations", {
    method: "POST",
    body: JSON.stringify({
      title: createConversationTitle(firstMessage),
    }),
  });
  activeConversationId = conversation.id;
  previousResponseId = undefined;
  await refreshConversationList();
  return activeConversationId;
}

async function persistMessage(role, content) {
  await authenticatedFetch(
    `/api/conversations/${encodeURIComponent(activeConversationId)}/messages`,
    {
      method: "POST",
      body: JSON.stringify({ role, content }),
    },
  );
}

async function persistPreviousResponseId(responseId) {
  await authenticatedFetch(
    `/api/conversations/${encodeURIComponent(activeConversationId)}`,
    {
      method: "PATCH",
      body: JSON.stringify({ previousResponseId: responseId }),
    },
  );
}

async function processAgentResponse(initialResponse, originalMessage) {
  let response = initialResponse;

  for (let round = 0; round < 10; round += 1) {
    previousResponseId = response.id;
    await persistPreviousResponseId(previousResponseId);

    const consentRequest = getOAuthConsentRequest(response);
    if (consentRequest) {
      addOAuthConsentMessage(consentRequest, originalMessage);
      return;
    }

    oauthConsentPending = false;
    const responseText = extractResponseText(response);
    if (responseText) {
      addMessage("assistant", responseText);
      await persistMessage("assistant", responseText);
    }

    const approvalRequests = getMcpApprovalRequests(response);
    if (approvalRequests.length === 0) {
      if (!responseText) {
        throw new Error(
          `The agent returned no text. Response status: ${response.status ?? "unknown"}.`,
        );
      }
      await refreshConversationList();
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
  activeConversationId = undefined;
  previousResponseId = undefined;
  oauthConsentPending = false;
  showConversationPrompt(
    "A new conversation is ready. What would you like to know?",
  );
  formStatus.textContent = "";
  formStatus.className = "form-status";
  closeConversationMenus();
  renderConversationList();
  setInteractionDisabled(false);
  input.focus();
}

function setInteractionDisabled(disabled) {
  requestInProgress = disabled;
  input.disabled = disabled;
  sendButton.disabled = disabled;
  for (const button of conversationList.querySelectorAll("button")) {
    button.disabled = disabled;
  }
  clearHistoryButton.disabled = disabled || conversations.length === 0;
  newChatButton.disabled = disabled;
}

async function deleteConversation(conversationId) {
  const conversation = conversations.find(
    (item) => item.id === conversationId,
  );
  if (
    !conversation ||
    !window.confirm(`Delete "${conversation.title}" and all of its messages?`)
  ) {
    return;
  }

  setInteractionDisabled(true);
  try {
    await authenticatedFetch(
      `/api/conversations/${encodeURIComponent(conversationId)}`,
      { method: "DELETE" },
    );
    if (conversationId === activeConversationId) {
      activeConversationId = undefined;
      previousResponseId = undefined;
      await refreshConversationList();
      if (conversations.length > 0) {
        await openConversation(conversations[0].id);
      } else {
        resetConversation();
      }
    } else {
      await refreshConversationList();
    }
  } finally {
    setInteractionDisabled(false);
  }
}

async function renameConversation(conversationId) {
  const conversation = conversations.find(
    (item) => item.id === conversationId,
  );
  if (!conversation) {
    return;
  }

  const enteredTitle = window.prompt("Rename chat", conversation.title);
  if (enteredTitle === null) {
    return;
  }

  const title = enteredTitle.trim();
  if (!title) {
    throw new Error("Chat name cannot be empty.");
  }
  if (title.length > 120) {
    throw new Error("Chat name cannot exceed 120 characters.");
  }
  if (title === conversation.title) {
    return;
  }

  setInteractionDisabled(true);
  try {
    await authenticatedFetch(
      `/api/conversations/${encodeURIComponent(conversationId)}`,
      {
        method: "PATCH",
        body: JSON.stringify({ title }),
      },
    );
    await refreshConversationList();
  } finally {
    setInteractionDisabled(false);
  }
}

async function clearHistory() {
  if (
    !window.confirm(
      "Clear all of your saved conversations? This cannot be undone.",
    )
  ) {
    return;
  }

  setInteractionDisabled(true);
  try {
    await authenticatedFetch("/api/conversations", { method: "DELETE" });
    conversations = [];
    resetConversation();
  } finally {
    setInteractionDisabled(false);
  }
}

async function showAuthenticatedView() {
  signedOut.hidden = true;
  chatPanel.hidden = false;

  const username = document.createElement("span");
  username.textContent = account.name || account.username;

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

  accountActions.replaceChildren(username, logout);
  setInteractionDisabled(true);
  formStatus.textContent = "Loading chat history...";
  await initializeHistory();
  setInteractionDisabled(false);
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
    await showAuthenticatedView();
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

newChatButton.addEventListener("click", resetConversation);

conversationList.addEventListener("click", (event) => {
  const item = event.target.closest(".conversation-item");
  if (!item) {
    return;
  }

  const conversationId = item.dataset.conversationId;
  const menuButton = event.target.closest(".conversation-menu-button");
  if (menuButton) {
    const menu = item.querySelector(".conversation-menu");
    const shouldOpen = menu.hidden;
    closeConversationMenus(shouldOpen ? conversationId : undefined);
    return;
  }

  if (event.target.closest(".conversation-delete")) {
    closeConversationMenus();
    deleteConversation(conversationId).catch((error) => {
      formStatus.textContent = error.message;
      formStatus.className = "form-status error";
      setInteractionDisabled(false);
    });
    return;
  }

  if (event.target.closest(".conversation-rename")) {
    closeConversationMenus();
    renameConversation(conversationId).catch((error) => {
      formStatus.textContent = error.message;
      formStatus.className = "form-status error";
      setInteractionDisabled(false);
    });
    return;
  }

  if (!event.target.closest(".conversation-open")) {
    return;
  }

  closeConversationMenus();
  setInteractionDisabled(true);
  openConversation(conversationId)
    .catch((error) => {
      formStatus.textContent = error.message;
      formStatus.className = "form-status error";
    })
    .finally(() => setInteractionDisabled(false));
});

document.addEventListener("click", (event) => {
  if (!event.target.closest(".conversation-menu-wrap")) {
    closeConversationMenus();
  }
});

clearHistoryButton.addEventListener("click", () => {
  clearHistory().catch((error) => {
    formStatus.textContent = error.message;
    formStatus.className = "form-status error";
    setInteractionDisabled(false);
  });
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = input.value.trim();
  if (!message) {
    return;
  }

  input.value = "";
  setInteractionDisabled(true);
  formStatus.textContent = "Saving your message...";
  formStatus.className = "form-status";

  try {
    await ensureConversation(message);
    addMessage("user", message);
    await persistMessage("user", message);
    formStatus.textContent = "The agent is working...";
    const result = await callAgent(message);
    await processAgentResponse(result, message);
    formStatus.textContent = "";
  } catch (error) {
    addMessage("assistant", "I could not complete that request.");
    formStatus.textContent = error.message;
    formStatus.className = "form-status error";
  } finally {
    if (!oauthConsentPending) {
      setInteractionDisabled(false);
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
