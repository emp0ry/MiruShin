const navToggle = document.querySelector(".nav-toggle");
const siteNav = navToggle
  ? document.getElementById(navToggle.getAttribute("aria-controls") || "")
  : document.querySelector(".site-nav");

if (navToggle && siteNav) {
  navToggle.addEventListener("click", () => {
    const isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
    navToggle.setAttribute("aria-label", isOpen ? "Close menu" : "Open menu");
  });

  siteNav.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      siteNav.classList.remove("is-open");
      navToggle.setAttribute("aria-expanded", "false");
      navToggle.setAttribute("aria-label", "Open menu");
    });
  });
}

const yearNode = document.querySelector("[data-year]");
if (yearNode) {
  yearNode.textContent = String(new Date().getFullYear());
}

const releaseApiUrl = "https://api.github.com/repos/emp0ry/MiruShin/releases/latest";
const releasePageUrl = "https://github.com/emp0ry/MiruShin/releases/latest";
const downloadTargets = [
  {
    key: "windows-setup",
    label: "Windows setup installer",
    pattern: /^MiruShin-windows-v.+-setup\.exe$/i,
  },
  {
    key: "windows-msi",
    label: "Windows MSI installer",
    pattern: /^MiruShin-windows-v.+-setup\.msi$/i,
  },
  {
    key: "windows-portable",
    label: "Windows portable ZIP",
    pattern: /^MiruShin-windows-v.+-portable\.zip$/i,
  },
  {
    key: "macos",
    label: "macOS DMG",
    pattern: /^MiruShin-macos-v.+\.dmg$/i,
  },
  {
    key: "ios",
    label: "iOS IPA",
    pattern: /^MiruShin-ios-v.+\.ipa$/i,
  },
  {
    key: "android",
    label: "Android and Android TV APK",
    pattern: /^MiruShin-android-v.+\.apk$/i,
  },
  {
    key: "linux-appimage",
    label: "Linux AppImage",
    pattern: /^MiruShin-linux-v.+\.AppImage$/i,
  },
  {
    key: "linux-deb",
    label: "Linux DEB package",
    pattern: /^MiruShin-linux-v.+\.deb$/i,
  },
  {
    key: "linux-targz",
    label: "Linux tar.gz archive",
    pattern: /^MiruShin-linux-v.+\.tar\.gz$/i,
  },
];

const releaseStatus = document.querySelector("[data-release-status]");
const downloadCards = [...document.querySelectorAll("[data-download-card]")];

const setDownloadFallback = (card) => {
  const link = card.querySelector("[data-download]");

  card.classList.add("is-missing");
  if (link) {
    link.href = releasePageUrl;
    link.textContent = "Open Release";
    link.setAttribute("target", "_blank");
    link.removeAttribute("download");
  }
};

const resolveDownloadLinks = async () => {
  if (!downloadCards.length) {
    return;
  }

  try {
    const response = await fetch(releaseApiUrl, {
      headers: { Accept: "application/vnd.github+json" },
    });

    if (!response.ok) {
      throw new Error(`GitHub release request failed: ${response.status}`);
    }

    const release = await response.json();
    const assets = Array.isArray(release.assets) ? release.assets : [];
    let resolvedCount = 0;

    downloadTargets.forEach((target) => {
      const card = document.querySelector(`[data-download-card="${target.key}"]`);
      const link = document.querySelector(`[data-download="${target.key}"]`);
      const asset = assets.find((item) => target.pattern.test(item.name || ""));

      if (!card || !link) {
        return;
      }

      if (!asset?.browser_download_url) {
        setDownloadFallback(card);
        if (release.html_url) {
          link.href = release.html_url;
        }
        return;
      }

      resolvedCount += 1;
      card.classList.add("is-ready");
      link.href = asset.browser_download_url;
      link.textContent = "Download";
      link.setAttribute("aria-label", `Download ${target.label}: ${asset.name}`);
      link.setAttribute("download", "");
      link.removeAttribute("target");
    });

    if (releaseStatus) {
      const releaseLabel = release.name || release.tag_name || "latest release";
      releaseStatus.textContent =
        resolvedCount === downloadTargets.length
          ? `Latest release: ${releaseLabel}`
          : `Latest release: ${releaseLabel} · ${resolvedCount}/${downloadTargets.length} files found`;
      releaseStatus.classList.add("is-loaded");
    }
  } catch (error) {
    downloadCards.forEach(setDownloadFallback);
    if (releaseStatus) {
      releaseStatus.textContent =
        "Could not check GitHub right now. Buttons open the release page.";
      releaseStatus.classList.add("is-error");
    }
  }
};

resolveDownloadLinks();

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const revealNodes = document.querySelectorAll(".reveal");
if (!reducedMotion && "IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver(
    (entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) {
          return;
        }
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    { threshold: 0.18, rootMargin: "0px 0px -40px 0px" },
  );

  revealNodes.forEach((node) => revealObserver.observe(node));
} else {
  revealNodes.forEach((node) => node.classList.add("is-visible"));
}

const sections = [...document.querySelectorAll("main section[id]")];
const sectionLinks = [...document.querySelectorAll('.site-nav a[href^="#"]')];

if (sections.length && sectionLinks.length && "IntersectionObserver" in window) {
  const activeMap = new Map(
    sectionLinks.map((link) => [link.getAttribute("href")?.slice(1), link]),
  );

  const sectionObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const link = activeMap.get(entry.target.id);
        if (!link) {
          return;
        }
        if (entry.isIntersecting) {
          sectionLinks.forEach((item) => item.classList.remove("is-active"));
          link.classList.add("is-active");
        }
      });
    },
    { threshold: 0.55 },
  );

  sections.forEach((section) => sectionObserver.observe(section));
}

const stage = document.querySelector(".hero-stage");
if (stage && !reducedMotion) {
  stage.addEventListener("pointermove", (event) => {
    const rect = stage.getBoundingClientRect();
    const offsetX = (event.clientX - rect.left) / rect.width - 0.5;
    const offsetY = (event.clientY - rect.top) / rect.height - 0.5;
    stage.style.setProperty("--tilt-x", `${offsetY * -8}deg`);
    stage.style.setProperty("--tilt-y", `${offsetX * 10}deg`);
    stage.style.setProperty("--float-x", `${offsetX * 18}px`);
    stage.style.setProperty("--float-y", `${offsetY * 18}px`);
  });

  stage.addEventListener("pointerleave", () => {
    stage.style.setProperty("--tilt-x", "0deg");
    stage.style.setProperty("--tilt-y", "0deg");
    stage.style.setProperty("--float-x", "0px");
    stage.style.setProperty("--float-y", "0px");
  });
}
