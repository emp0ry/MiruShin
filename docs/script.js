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
