// Start the editor in the page, and list the builds of the latest release.
const stage = document.querySelector("[data-app-stage]");

for (const button of document.querySelectorAll("[data-open]")) {
  button.addEventListener("click", () => {
    stage.querySelector("iframe")?.remove();
    const frame = document.createElement("iframe");
    frame.src = button.dataset.open;
    frame.title = "UXML Editor";
    frame.allow = "fullscreen; clipboard-read; clipboard-write";
    stage.append(frame);
    stage.classList.add("is-running");
    frame.focus();
  });
}

const PLATFORMS = [
  [/windows/i, "Windows x64"],
  [/linux/i, "Linux x86_64"],
  [/mac/i, "macOS"],
];

async function showRelease() {
  const status = document.querySelector("[data-release-status]");
  const list = document.querySelector("[data-release-files]");
  if (!status || !list) return;
  try {
    const response = await fetch("https://api.github.com/repos/splatterfacegames/uxml-editor/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) return; // 404: no release yet; the static text says so.
    const release = await response.json();
    const assets = (release.assets || []).filter((a) => /\.(zip|tar\.gz)$/i.test(a.name));
    if (assets.length === 0) return;
    status.textContent = `${release.name || release.tag_name}, released ${new Date(release.published_at).toLocaleDateString()}.`;
    for (const asset of assets) {
      const platform = PLATFORMS.find(([re]) => re.test(asset.name));
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.className = "button button-primary";
      link.href = asset.browser_download_url;
      link.textContent = `${platform ? platform[1] : asset.name} (${(asset.size / 1048576).toFixed(0)} MB)`;
      item.append(link);
      list.append(item);
    }
    list.hidden = false;
  } catch {
    // Offline or rate limited: keep the static text.
  }
}

showRelease();

// The reel plays only when motion is welcome; else it shows its poster
// and the controls.
const reel = document.querySelector(".reel-video");
if (reel && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  reel.removeAttribute("autoplay");
  reel.pause();
  reel.controls = true;
}
