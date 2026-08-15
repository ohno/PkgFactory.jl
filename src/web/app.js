const state = {
  accessToken: "",
  config: null,
  owner: null,
  polling: false,
  availability: null,
  availabilityTimer: null,
  availabilityRequest: 0,
};

const $ = (selector) => document.querySelector(selector);
const panels = ["#connect-panel", "#package-form", "#creating-panel", "#success-panel"];

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  if (state.accessToken) headers.Authorization = `Bearer ${state.accessToken}`;
  const response = await fetch(path, { ...options, headers });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status}).`);
  return data;
}

function showPanel(selector) {
  panels.forEach((panel) => { $(panel).hidden = panel !== selector; });
}

function setStep(active) {
  document.querySelectorAll(".workflow-card[data-step]").forEach((card) => {
    const number = Number(card.dataset.step);
    card.classList.toggle("is-active", number === active);
    card.classList.toggle("is-complete", number < active);
  });
}

function setError(message = "") {
  const notice = $("#form-error");
  notice.textContent = message;
  notice.hidden = !message;
}

function setConnected(owner) {
  state.owner = owner;
  $("#account").classList.add("is-connected");
  $("#account-label").textContent = `Connected as @${owner.login}`;
}

function setDefaultAuthor(owner) {
  $("#authors").value = String(owner.name || owner.login).trim();
}

function setAvailability(status, message) {
  state.availability = status;
  const notice = $("#package-availability");
  notice.textContent = message;
  notice.className = `availability-status${status === "available" ? " is-available" : ["existing", "invalid"].includes(status) ? " is-unavailable" : message ? " is-checking" : ""}`;
  const input = $("#package-name");
  const blockedExisting = status === "existing" && !$("#resume").checked;
  const validationMessage = status === "invalid" ? message : blockedExisting ? "This repository already exists. Enable Resume interrupted setup to continue." : "";
  input.setCustomValidity(validationMessage);
}

async function checkPackageAvailability() {
  const request = ++state.availabilityRequest;
  const payload = packagePayload();
  if (!state.accessToken || !payload.owner || !payload.package_name) {
    setAvailability(null, "");
    return null;
  }
  setAvailability(null, "Checking GitHub…");
  try {
    const result = await api("/api/github/repository-availability", {
      method: "POST",
      body: JSON.stringify({ owner: payload.owner, package_name: payload.package_name }),
    });
    if (request !== state.availabilityRequest) return null;
    if (result.available) {
      setAvailability("available", `${result.repository} is available.`);
      return "available";
    }
    setAvailability("existing", `${result.repository} already exists. Enable Resume interrupted setup to continue.`);
    return "existing";
  } catch (error) {
    if (request !== state.availabilityRequest) return null;
    setAvailability("invalid", error.message);
    return "invalid";
  }
}

function scheduleAvailabilityCheck() {
  clearTimeout(state.availabilityTimer);
  state.availabilityRequest += 1;
  setAvailability(null, "Waiting for input…");
  state.availabilityTimer = setTimeout(checkPackageAvailability, 450);
}

async function loadConfiguration() {
  state.config = await api("/api/config");
  const templates = $("#template");
  templates.replaceChildren();
  [...state.config.templates].sort((a, b) => a === "all-in-one" ? -1 : b === "all-in-one" ? 1 : a.localeCompare(b)).forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    templates.append(option);
  });
}

async function loadOwners() {
  const { owners } = await api("/api/github/owners");
  const select = $("#owner");
  select.replaceChildren();
  owners.forEach((owner) => {
    const option = document.createElement("option");
    option.value = owner.login;
    option.textContent = owner.kind === "organization" ? `${owner.name} (@${owner.login}) · organization` : `${owner.name} (@${owner.login})`;
    select.append(option);
  });
  setConnected(owners[0]);
  setDefaultAuthor(owners[0]);
  await checkPackageAvailability();
}

async function pollForToken(deviceCode, interval) {
  state.polling = true;
  let delay = Math.max(Number(interval) || 5, 5);
  while (state.polling) {
    await new Promise((resolve) => setTimeout(resolve, delay * 1000));
    const result = await api("/api/oauth/token", {
      method: "POST",
      body: JSON.stringify({ device_code: deviceCode }),
    });
    if (result.access_token) {
      const grantedScopes = new Set(String(result.scope || "").split(/[\s,]+/).filter(Boolean));
      const requiredScopes = ["repo", "workflow"];
      const missingScopes = requiredScopes.filter((scope) => !grantedScopes.has(scope));
      if (missingScopes.length) {
        throw new Error(`GitHub did not grant the required ${missingScopes.join(", ")} permission. Reconnect and approve all requested permissions.`);
      }
      state.accessToken = result.access_token;
      state.polling = false;
      $("#device-status").textContent = "Authorized. Loading your GitHub account…";
      await loadOwners();
      showPanel("#package-form");
      setStep(2);
      return;
    }
    if (result.error === "authorization_pending") continue;
    if (result.error === "slow_down") {
      delay += Number(result.interval) || 5;
      continue;
    }
    throw new Error(result.error_description || "GitHub authorization was not completed.");
  }
}

async function connectGitHub() {
  const button = $("#connect-button");
  $("#connect-error").hidden = true;
  button.disabled = true;
  button.textContent = "Requesting a GitHub code…";
  try {
    const device = await api("/api/oauth/device", { method: "POST", body: "{}" });
    $("#device-code").textContent = device.user_code;
    $("#verification-link").href = device.verification_uri;
    $("#device-card").hidden = false;
    button.hidden = true;
    await pollForToken(device.device_code, device.interval);
  } catch (error) {
    state.polling = false;
    $("#device-status").textContent = error.message;
    $("#connect-error").textContent = error.message;
    $("#connect-error").hidden = false;
    button.hidden = false;
    button.disabled = false;
    button.textContent = "Try GitHub connection again";
  }
}

function packagePayload() {
  const packageName = $("#package-name").value.trim().replace(/\.jl$/i, "");
  return {
    owner: $("#owner").value,
    package_name: packageName,
    authors: $("#authors").value.split(",").map((author) => author.trim()).filter(Boolean),
    description: $("#description").value.trim(),
    template: $("#template").value,
    visibility: $("#visibility").value,
    commit_message: $("#commit-message").value.trim(),
    codecov_token: $("#codecov-token").value.trim(),
    resume: $("#resume").checked,
  };
}

async function createPackage(event) {
  event.preventDefault();
  setError();
  const payload = packagePayload();
  if (!payload.authors.length) {
    setError("Enter at least one author.");
    return;
  }
  const availability = await checkPackageAvailability();
  if (availability !== "available" && !(availability === "existing" && payload.resume)) {
    setError($("#package-availability").textContent || "Enter a valid package name.");
    $("#package-name").reportValidity();
    return;
  }
  showPanel("#creating-panel");
  setStep(5);
  try {
    const result = await api("/api/packages", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    $("#success-copy").textContent = `${result.repository} is ready with its initial package structure and automation.`;
    $("#repository-link").href = result.url;
    showPanel("#success-panel");
    setStep(6);
  } catch (error) {
    showPanel("#package-form");
    setStep(2);
    setError(error.message);
    $("#form-error").scrollIntoView({ behavior: "smooth", block: "center" });
  } finally {
    $("#codecov-token").value = "";
  }
}

function createAnother() {
  $("#package-form").reset();
  $("#commit-message").value = "Using PkgFactory.jl";
  if (state.owner) setDefaultAuthor(state.owner);
  setError();
  showPanel("#package-form");
  setStep(2);
  checkPackageAvailability();
}

$("#connect-button").addEventListener("click", connectGitHub);
$("#copy-code").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("#device-code").textContent);
  $("#copy-code").textContent = "Copied";
});
$("#package-form").addEventListener("submit", createPackage);
$("#create-another").addEventListener("click", createAnother);
$("#package-name").addEventListener("input", scheduleAvailabilityCheck);
$("#owner").addEventListener("change", checkPackageAvailability);
$("#resume").addEventListener("change", () => setAvailability(state.availability, $("#package-availability").textContent));

loadConfiguration().catch((error) => {
  $("#connect-button").disabled = true;
  $("#connect-button").textContent = `Unable to load PkgFactory: ${error.message}`;
});
