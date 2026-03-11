const OWNER = "jtrefon";
const REPO = "ai-ide";
const API_URL = `https://api.github.com/repos/${OWNER}/${REPO}/releases`;
const REPO_URL = `https://github.com/${OWNER}/${REPO}`;

const statusNode = document.getElementById("release-status");
const latestVersionNode = document.getElementById("latest-version");
const latestSummaryNode = document.getElementById("latest-summary");
const latestDateNode = document.getElementById("latest-date");
const latestAssetsNode = document.getElementById("latest-assets");
const latestActionsNode = document.getElementById("latest-actions");
const releaseListNode = document.getElementById("release-list");
const refreshButton = document.getElementById("refresh-releases");

function formatDate(value) {
  if (!value) {
    return "-";
  }

  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(new Date(value));
}

function pickAsset(assets, matcher) {
  return assets.find((asset) => matcher.test(asset.name));
}

function summarizeRelease(release) {
  const body = (release.body || "")
    .replace(/[`#>*_-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!body) {
    return "Release notes are available on GitHub.";
  }

  return body.length > 180 ? `${body.slice(0, 177)}...` : body;
}

function assetLinks(release) {
  const dmg = pickAsset(release.assets, /\.dmg$/i);
  const zip = pickAsset(release.assets, /\.zip$/i);
  const links = [];

  if (dmg) {
    links.push(`<a class="button button-primary" href="${dmg.browser_download_url}">Download DMG</a>`);
  }

  if (zip) {
    links.push(`<a class="button button-secondary" href="${zip.browser_download_url}">Download ZIP</a>`);
  }

  links.push(`<a class="button button-secondary" href="${release.html_url}">Release Notes</a>`);
  return links.join("");
}

function releaseArchiveItem(release) {
  const links = release.assets
    .filter((asset) => /\.(dmg|zip)$/i.test(asset.name))
    .map((asset) => {
      const label = asset.name.toLowerCase().endsWith(".dmg") ? "DMG" : "ZIP";
      return `<a class="release-link" href="${asset.browser_download_url}">${label}</a>`;
    })
    .join("");

  const notesLink = `<a class="release-link" href="${release.html_url}">Notes</a>`;

  return `
    <article class="release-item">
      <header>
        <strong class="release-tag">${release.name || release.tag_name}</strong>
        <span>${formatDate(release.published_at)}</span>
      </header>
      <p>${summarizeRelease(release)}</p>
      <div class="release-links">${links}${notesLink}</div>
    </article>
  `;
}

function showError(message) {
  statusNode.textContent = "Release feed unavailable";
  latestVersionNode.textContent = "Download from GitHub";
  latestSummaryNode.textContent = message;
  latestDateNode.textContent = "-";
  latestAssetsNode.textContent = "-";
  latestActionsNode.innerHTML = `<a class="button button-primary" href="${REPO_URL}/releases">Open Releases</a>`;
  releaseListNode.innerHTML = `<p class="release-empty">${message}</p>`;
}

async function loadReleases() {
  statusNode.textContent = "Refreshing release metadata…";
  refreshButton.disabled = true;

  try {
    const response = await fetch(API_URL, {
      headers: {
        Accept: "application/vnd.github+json"
      }
    });

    if (!response.ok) {
      throw new Error(`GitHub API returned ${response.status}.`);
    }

    const releases = await response.json();
    const published = releases.filter((release) => !release.draft);

    if (published.length === 0) {
      showError("No public releases are published yet.");
      return;
    }

    const latest = published.find((release) => !release.prerelease) || published[0];
    const assetCount = latest.assets.length;

    statusNode.textContent = "Live from GitHub Releases";
    latestVersionNode.textContent = latest.name || latest.tag_name;
    latestSummaryNode.textContent = summarizeRelease(latest);
    latestDateNode.textContent = formatDate(latest.published_at);
    latestAssetsNode.textContent = `${assetCount} asset${assetCount === 1 ? "" : "s"}`;
    latestActionsNode.innerHTML = assetLinks(latest);
    releaseListNode.innerHTML = published
      .slice(0, 8)
      .map(releaseArchiveItem)
      .join("");
  } catch (error) {
    showError("GitHub release data could not be loaded right now. Use the releases page directly.");
  } finally {
    refreshButton.disabled = false;
  }
}

refreshButton.addEventListener("click", loadReleases);
loadReleases();
