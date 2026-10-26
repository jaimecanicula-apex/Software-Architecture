// File library: list, upload, download and delete files in one Blob container,
// as the signed-in user. MSAL.js gets the user's own Entra token for Azure
// Storage; there is no account key and no server code. The only access rule is
// the user's role on the container. No build step; MSAL.js is the pinned copy
// in vendor/.
(function () {
  "use strict";

  var STORAGE_SCOPE = "https://storage.azure.com/user_impersonation";
  var API_VERSION = "2023-11-03";
  // Defender for Storage writes this index tag on every scanned blob.
  var SCAN_TAG = "Malware Scanning scan result";
  var SCAN_MALICIOUS = "Malicious";

  var statusEl = document.getElementById("files-status");
  var form = document.getElementById("upload-form");
  var input = document.getElementById("file-input");
  var rulesEl = document.getElementById("upload-rules");
  var table = document.getElementById("files-table");
  var body = document.getElementById("files-body");

  var config, msal, account, base;

  function setStatus(text, isError) {
    statusEl.textContent = text;
    statusEl.classList.toggle("is-error", Boolean(isError));
  }

  function friendly(error) {
    if (error && error.status === 403) {
      return "You are signed in, but your account has no access to the file library. Ask the site owner to add you to the allowed group.";
    }
    if (error && error.status === 404) {
      return "The file library was not found. Ask the site owner to check the storage settings.";
    }
    if (error instanceof TypeError) {
      return "Could not reach storage. Check that you are on the APEX network and try again.";
    }
    return (error && error.message) || "Something went wrong. Try again.";
  }

  async function getToken() {
    try {
      var result = await msal.acquireTokenSilent({ scopes: [STORAGE_SCOPE], account: account });
      return result.accessToken;
    } catch (error) {
      // Consent or a fresh sign-in is needed: leave the page and come back.
      await msal.acquireTokenRedirect({ scopes: [STORAGE_SCOPE], account: account });
      return new Promise(function () {}); // the redirect ends this page
    }
  }

  async function blobFetch(path, options) {
    options = options || {};
    var headers = Object.assign(
      { Authorization: "Bearer " + (await getToken()), "x-ms-version": API_VERSION },
      options.headers
    );
    var response = await fetch(base + path, { method: options.method || "GET", headers: headers, body: options.body });
    if (!response.ok) {
      var error = new Error("Storage returned " + response.status + ".");
      error.status = response.status;
      throw error;
    }
    return response;
  }

  function blobPath(name) {
    return "/" + config.container + "/" + encodeURIComponent(name);
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  function text(node, value) {
    node.textContent = value;
    return node;
  }

  // Blob names are typed by users, so they only ever go in as text, never as HTML.
  function actionButton(label, name, handler) {
    var button = text(document.createElement("button"), label);
    button.type = "button";
    button.className = "files__action";
    button.setAttribute("aria-label", label + " " + name);
    button.addEventListener("click", handler);
    return button;
  }

  function render(files) {
    body.textContent = "";
    files.forEach(function (file) {
      var row = document.createElement("tr");
      row.appendChild(text(document.createElement("td"), file.name));
      row.appendChild(text(document.createElement("td"), formatSize(file.size)));
      row.appendChild(text(document.createElement("td"), file.modified ? new Date(file.modified).toLocaleString() : ""));
      var actions = document.createElement("td");
      actions.className = "files__actions";
      actions.appendChild(actionButton("Download", file.name, function () { download(file.name); }));
      actions.appendChild(actionButton("Delete", file.name, function () { remove(file.name); }));
      row.appendChild(actions);
      body.appendChild(row);
    });
    table.hidden = files.length === 0;
  }

  async function list() {
    var files = [];
    var hidden = 0;
    var marker = "";
    do {
      var query = "?restype=container&comp=list&include=tags" + (marker ? "&marker=" + encodeURIComponent(marker) : "");
      var xml = new DOMParser().parseFromString(await (await blobFetch("/" + config.container + query)).text(), "application/xml");
      xml.querySelectorAll("Blob").forEach(function (blob) {
        var flagged = Array.prototype.some.call(blob.querySelectorAll("Tags Tag"), function (tag) {
          return tag.querySelector("Key").textContent === SCAN_TAG && tag.querySelector("Value").textContent === SCAN_MALICIOUS;
        });
        if (flagged) {
          hidden += 1;
          return;
        }
        var modified = blob.querySelector("Last-Modified");
        files.push({
          name: blob.querySelector("Name").textContent,
          size: Number(blob.querySelector("Content-Length").textContent),
          modified: modified ? modified.textContent : ""
        });
      });
      var next = xml.querySelector("NextMarker");
      marker = next ? next.textContent : "";
    } while (marker);

    files.sort(function (a, b) { return a.name.localeCompare(b.name); });
    render(files);
    var message = files.length === 1 ? "1 file." : files.length + " files.";
    if (hidden) message += " " + hidden + (hidden === 1 ? " file was" : " files were") + " hidden because malware scanning flagged " + (hidden === 1 ? "it." : "them.");
    setStatus(files.length ? message : "The library is empty." + (hidden ? " " + message : ""));
    return files;
  }

  async function download(name) {
    try {
      setStatus("Downloading " + name + "…");
      var blob = await (await blobFetch(blobPath(name))).blob();
      var url = URL.createObjectURL(blob);
      var link = document.createElement("a");
      link.href = url;
      link.download = name;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
      setStatus("Downloaded " + name + ".");
    } catch (error) {
      setStatus(friendly(error), true);
    }
  }

  async function remove(name) {
    if (!window.confirm("Delete " + name + "? It can be recovered by the site operators for a limited time.")) return;
    try {
      await blobFetch(blobPath(name), { method: "DELETE" });
      await list();
      setStatus("Deleted " + name + ".");
    } catch (error) {
      setStatus(friendly(error), true);
    }
  }

  // The limits come from configuration and are advice to users, not enforcement.
  function check(file) {
    var dot = file.name.lastIndexOf(".");
    var extension = dot < 0 ? "" : file.name.slice(dot).toLowerCase();
    if (config.allowedExtensions.indexOf(extension) < 0) {
      return "This file type is not allowed. Allowed: " + config.allowedExtensions.join(", ") + ".";
    }
    if (file.size > config.maxUploadMb * 1024 * 1024) {
      return "This file is larger than " + config.maxUploadMb + " MB.";
    }
    if (file.size === 0) return "This file is empty.";
    return "";
  }

  async function upload(event) {
    event.preventDefault();
    var file = input.files[0];
    if (!file) return;
    var problem = check(file);
    if (problem) {
      setStatus(problem, true);
      return;
    }
    try {
      var existing = Array.prototype.some.call(body.querySelectorAll("tr"), function (row) {
        return row.firstChild.textContent === file.name;
      });
      if (existing && !window.confirm(file.name + " already exists. Replace it? The old version can be recovered by the site operators for a limited time.")) return;
      setStatus("Uploading " + file.name + "…");
      await blobFetch(blobPath(file.name), {
        method: "PUT",
        headers: { "x-ms-blob-type": "BlockBlob", "Content-Type": file.type || "application/octet-stream" },
        body: file
      });
      form.reset();
      await list();
      setStatus("Uploaded " + file.name + ".");
    } catch (error) {
      setStatus(friendly(error), true);
    }
  }

  async function start() {
    try {
      config = await (await fetch("files-config.json", { credentials: "same-origin" })).json();
    } catch (error) {
      setStatus("The file library is not configured for this site yet.", true);
      return;
    }
    base = "https://" + config.storageAccount + ".blob.core.windows.net";

    msal = new window.msal.PublicClientApplication({
      auth: {
        clientId: config.clientId,
        authority: "https://login.microsoftonline.com/" + config.tenantId,
        redirectUri: window.location.origin + "/files.html"
      },
      cache: { cacheLocation: "sessionStorage" }
    });
    await msal.initialize();

    try {
      var redirected = await msal.handleRedirectPromise();
      account = (redirected && redirected.account) || msal.getAllAccounts()[0];
      if (!account) {
        await msal.loginRedirect({ scopes: [STORAGE_SCOPE] });
        return;
      }
      msal.setActiveAccount(account);

      rulesEl.textContent = "Allowed: " + config.allowedExtensions.join(", ") + ". Up to " + config.maxUploadMb + " MB.";
      form.hidden = false;
      form.addEventListener("submit", upload);
      await list();
    } catch (error) {
      setStatus(friendly(error), true);
    }
  }

  start();
})();
