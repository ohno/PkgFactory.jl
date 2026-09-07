const state = {
  accessToken: "",
  config: null,
  owner: null,
  polling: false,
  availability: null,
  availabilityTimer: null,
  availabilityRequest: 0,
  activeStep: 1,
  automationReviewed: false,
  creationStatus: "idle",
};

const $ = (selector) => document.querySelector(selector);

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  if (state.accessToken) headers.Authorization = `Bearer ${state.accessToken}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), path === "/api/packages" ? 120000 : 45000);
  try {
    const response = await fetch(path, { ...options, headers, signal: controller.signal });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status}).`);
    return data;
  } finally {
    clearTimeout(timeout);
  }
}

function setStep(active) {
  state.activeStep = active;
  updateWorkflowProgress();
}

function updateWorkflowProgress() {
  const payload = packagePayload();
  const repositoryAvailable = state.availability === "available" ||
    (state.availability === "existing" && payload.resume);
  const completed = {
    1: Boolean(state.owner),
    2: Boolean(state.owner && payload.owner && payload.package_name && repositoryAvailable),
    3: Boolean(state.owner && payload.authors.length && payload.description && payload.template && payload.commit_message),
    4: Boolean(state.owner && payload.template && (state.automationReviewed || payload.template === "minimum")),
    5: state.creationStatus === "success",
  };
  document.querySelectorAll("#package-form .workflow-card[data-step]").forEach((card) => {
    const number = Number(card.dataset.step);
    if (number < 2 || number > 4) return;
    completed[number] = completed[number] && [...card.querySelectorAll("input, select, textarea")]
      .every((input) => input.disabled || input.validity.valid);
    card.querySelector(".step-state").textContent = completed[number] ? "Ready" : number === 4 ? "Optional" : "Required";
  });
  const active = state.activeStep === 2
    ? [2, 3, 4].find((number) => !completed[number]) || 5
    : state.activeStep;
  document.querySelectorAll(".workflow-card[data-step]").forEach((card) => {
    const number = Number(card.dataset.step);
    const complete = completed[number] || false;
    card.classList.toggle("is-active", number === active && !complete);
    card.classList.toggle("is-complete", complete);
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
  $("#connect-state").textContent = "Completed";
  $("#connect-description").textContent = `Successfully authorized as @${owner.login}. GitHub is connected for this browser session.`;
  $("#connect-actions").hidden = true;
  updateWorkflowProgress();
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
  updateWorkflowProgress();
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
  const templateOrder = ["all-in-one", "simple", "minimum"];
  const rank = (name) => templateOrder.includes(name) ? templateOrder.indexOf(name) : templateOrder.length;
  [...state.config.templates].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b)).forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    templates.append(option);
  });
  updateTemplateAutomation();
}

function setCreationStatus(status) {
  state.creationStatus = status;
  const pending = status === "checking" || status === "creating";
  $("#package-fields").disabled = status !== "idle";
  $("#create-button").disabled = pending;
  $("#create-button").hidden = status === "success";
  $("#creating-panel").hidden = !pending;
  $("#creation-message").textContent = status === "checking"
    ? "Checking repository availability…"
    : "Building your package…";
  $("#success-panel").hidden = status !== "success";
  $("#create-state").textContent = status === "success" ? "Completed" : pending ? "In progress" : "Final step";
  setStep(status === "idle" ? 2 : 5);
}

function updateTemplateAutomation() {
  const minimum = $("#template").value === "minimum";
  $("#documenter-row").classList.toggle("is-disabled", minimum);
  $("#documenter-state").textContent = minimum ? "Not needed" : "Automatic";
  $("#documenter-description").textContent = minimum
    ? "The minimum template does not include documentation deployment."
    : "Deploy key and DOCUMENTER_KEY repository secret";
  $("#codecov-field").classList.toggle("is-disabled", minimum);
  $("#codecov-token").disabled = minimum;
  $("#codecov-token").placeholder = minimum ? "Not needed for minimum" : "Leave blank to skip CODECOV_TOKEN";
  $("#codecov-description").textContent = minimum
    ? "No input needed: the minimum template does not use Codecov."
    : "Optional: leave blank to skip configuring Codecov.";
  $("#automation-description").textContent = minimum
    ? "Documenter and Codecov are not needed for minimum. You can still resume a previous setup."
    : "Documenter keys are generated automatically. Add coverage or resume a previous setup here.";
  $("#create-description").textContent = minimum
    ? "PkgFactory will create the repository and commit the minimum template with CI."
    : "PkgFactory will create the repository, commit the template, add gh-pages, and configure secrets.";
  updateWorkflowProgress();
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
      $("#package-form").hidden = false;
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
    $("#copy-code").textContent = "Copy code";
    $("#device-status").textContent = "Waiting for authorization…";
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
    codecov_token: $("#template").value === "minimum" ? "" : $("#codecov-token").value.trim(),
    resume: $("#resume").checked,
  };
}

async function createPackage(event) {
  event.preventDefault();
  if (state.creationStatus !== "idle") return;
  setError();
  const payload = packagePayload();
  if (!payload.authors.length) {
    setError("Enter at least one author.");
    return;
  }
  clearTimeout(state.availabilityTimer);
  setCreationStatus("checking");
  try {
    const availability = await checkPackageAvailability();
    if (availability !== "available" && !(availability === "existing" && payload.resume)) {
      setError($("#package-availability").textContent || "Enter a valid package name.");
      return;
    }
    // Submitting also confirms the choice to leave optional settings blank.
    state.automationReviewed = true;
    setCreationStatus("creating");
    const result = await api("/api/packages", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    $("#success-copy").textContent = `${result.repository} is ready with its initial package structure and automation.`;
    $("#repository-link").href = result.url;
    setCreationStatus("success");
  } catch (error) {
    let message = error.name === "AbortError"
      ? "The request timed out. GitHub processing may still be running."
      : error.message;
    if (state.creationStatus === "creating") {
      try {
        const status = await api("/api/github/repository-status", {
          method: "POST",
          body: JSON.stringify({ owner: payload.owner, package_name: payload.package_name }),
        });
        const guidance = {
          not_found: "Repository not found with this account. Check GitHub before trying again.",
          unverified: "An unverified repository exists. Inspect it on GitHub; automatic resume is unavailable.",
          files_committed: "Template files were committed. Check GitHub, then select Resume with the original settings.",
          complete: "GitHub records a completed PkgFactory setup. Inspect the repository before taking further action.",
        };
        message += ` ${guidance[status.state] || "Check the repository on GitHub."}`;
      } catch {
        message += " Status could not be checked. Inspect GitHub before retrying.";
      }
    }
    setError(message);
    $("#form-error").scrollIntoView({ behavior: "smooth", block: "center" });
  } finally {
    if (state.creationStatus !== "checking") $("#codecov-token").value = "";
    if (state.creationStatus !== "success") setCreationStatus("idle");
  }
}

function createAnother() {
  if (state.creationStatus !== "success") return;
  $("#package-form").reset();
  state.automationReviewed = false;
  clearTimeout(state.availabilityTimer);
  state.availabilityRequest += 1;
  setAvailability(null, "");
  updateTemplateAutomation();
  $("#commit-message").value = "Using PkgFactory.jl";
  if (state.owner) setDefaultAuthor(state.owner);
  setError();
  setCreationStatus("idle");
  checkPackageAvailability();
}

function updateInputProgress(event) {
  if (event.target.closest('[data-step="4"]')) state.automationReviewed = true;
  updateWorkflowProgress();
}

async function copyDeviceCode() {
  try {
    await navigator.clipboard.writeText($("#device-code").textContent);
    $("#copy-code").textContent = "Copied";
    $("#device-status").textContent = "Code copied. Paste it on GitHub to authorize this session.";
  } catch {
    $("#device-status").textContent = "Could not copy automatically. Copy the displayed code manually and paste it on GitHub.";
  }
}

$("#connect-button").addEventListener("click", connectGitHub);
$("#copy-code").addEventListener("click", copyDeviceCode);
// Start copying in the click gesture while the link opens its tab normally.
$("#verification-link").addEventListener("click", copyDeviceCode);
$("#package-form").addEventListener("submit", createPackage);
$("#package-form").addEventListener("input", updateInputProgress);
$("#package-form").addEventListener("change", updateInputProgress);
$("#create-another").addEventListener("click", createAnother);
$("#package-name").addEventListener("input", scheduleAvailabilityCheck);
$("#owner").addEventListener("change", checkPackageAvailability);
$("#template").addEventListener("change", updateTemplateAutomation);
$("#resume").addEventListener("change", () => setAvailability(state.availability, $("#package-availability").textContent));

loadConfiguration().catch((error) => {
  $("#connect-button").disabled = true;
  $("#connect-button").textContent = `Unable to load PkgFactory: ${error.message}`;
});
