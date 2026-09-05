const desktopNav = document.querySelector(".header-inner > .site-nav");
if (desktopNav && typeof HTMLDialogElement.prototype.showModal === "function") {
  const toggle = document.createElement("button");
  toggle.className = "mobile-menu-toggle gallery-icon-button";
  toggle.type = "button";
  toggle.setAttribute("aria-label", "메뉴 열기");
  toggle.setAttribute("aria-haspopup", "dialog");
  toggle.setAttribute("aria-controls", "mobile-menu");
  toggle.setAttribute("aria-expanded", "false");
  // Lucide Menu and X, matching the gallery controls.
  toggle.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"></path></svg>';
  const menu = document.createElement("dialog");
  menu.id = "mobile-menu";
  menu.className = "mobile-menu";
  menu.setAttribute("aria-label", "주요 메뉴");
  menu.innerHTML = '<div class="mobile-menu-panel"><button class="gallery-icon-button mobile-menu-close" type="button" aria-label="메뉴 닫기" autofocus><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"></path></svg></button></div>';
  menu.querySelector(".mobile-menu-panel").append(desktopNav.cloneNode(true));
  document.body.append(menu);
  desktopNav.after(toggle);
  document.documentElement.classList.add("mobile-navigation-ready");
  const mobileWidth = window.matchMedia("(max-width: 820px)");
  const positionMenu = () => {
    const bounds = toggle.getBoundingClientRect();
    menu.style.setProperty("--menu-top", `${bounds.bottom + 4}px`);
    menu.style.setProperty("--menu-right", `${document.documentElement.clientWidth - bounds.right}px`);
    menu.style.setProperty("--menu-toggle-top", `${bounds.top}px`);
  };
  toggle.addEventListener("click", () => {
    positionMenu();
    menu.showModal();
    toggle.setAttribute("aria-expanded", "true");
    document.documentElement.classList.add("menu-open");
  });
  menu.querySelector(".mobile-menu-close").addEventListener("click", () => menu.close());
  menu.addEventListener("click", (event) => {
    if (event.target === menu || event.target.closest("a")) menu.close();
  });
  menu.addEventListener("close", () => {
    if (menu.open) return;
    toggle.setAttribute("aria-expanded", "false");
    document.documentElement.classList.remove("menu-open");
    if (mobileWidth.matches) toggle.focus({ preventScroll: true });
  });
  mobileWidth.addEventListener("change", () => {
    if (!mobileWidth.matches && menu.open) menu.close();
  });
  window.addEventListener("resize", () => {
    if (menu.open) positionMenu();
  });
}

const markerColors = [
  "var(--brand-pink)",
  "var(--brand-yellow)",
  "var(--brand-green)",
  "var(--brand-blue)",
];

const currentMarkerColor = markerColors[Math.floor(Math.random() * markerColors.length)];

document.querySelectorAll(".site-nav a, .footer-links a").forEach((link) => {
  if (link.matches('[aria-current="page"]')) {
    link.style.setProperty("--menu-marker", currentMarkerColor);
    return;
  }

  let previousColor;

  const chooseMarkerColor = () => {
    const choices = markerColors.filter((color) => color !== previousColor);
    const color = choices[Math.floor(Math.random() * choices.length)];
    link.style.setProperty("--menu-marker", color);
    previousColor = color;
  };

  link.addEventListener("pointerenter", chooseMarkerColor);
  link.addEventListener("focus", () => {
    if (link.matches(":focus-visible")) chooseMarkerColor();
  });
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const brand = document.querySelector(".site-header .brand");
if (brand) {
  const highlightBrand = () => {
    if (reducedMotion.matches || document.hidden || brand.classList.contains("is-highlighting")) return false;
    brand.classList.add("is-highlighting");
    return true;
  };
  brand.addEventListener("animationend", (event) => {
    if (event.animationName === "brand-highlight" && event.target === brand.querySelector(".brand-drawer")) {
      brand.classList.remove("is-highlighting");
    }
  });
  brand.addEventListener("pointerenter", (event) => {
    if (event.pointerType === "mouse") highlightBrand();
  });
  brand.addEventListener("focus", () => {
    if (brand.matches(":focus-visible")) highlightBrand();
  });
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) brand.classList.remove("is-highlighting");
  });
  // Play once per tab visit, including navigation between the three static pages.
  let hasSeenHighlight = false;
  try { hasSeenHighlight = sessionStorage.getItem("brand-highlight-seen") === "1"; } catch { /* Storage can be disabled. */ }
  if (!hasSeenHighlight) {
    window.setTimeout(() => {
      if (!highlightBrand()) return;
      try { sessionStorage.setItem("brand-highlight-seen", "1"); } catch { /* Keep the effect available without storage. */ }
    }, 450);
  }
}

const faqHover = window.matchMedia("(hover: hover) and (pointer: fine)");
document.querySelectorAll(".faq details").forEach((item) => {
  let angle = 0;
  item.addEventListener("pointerenter", (event) => {
    if (item.open || event.pointerType === "touch" || !faqHover.matches || reducedMotion.matches) return;
    angle += 90;
    item.style.setProperty("--faq-icon-angle", `${angle}deg`);
  });
});

const screenshotTrack = document.querySelector(".screenshot-track");

if (screenshotTrack) {
  const links = Array.from(screenshotTrack.querySelectorAll(".screenshot-link"));
  const controls = document.querySelector(".gallery-controls");
  const previous = controls.querySelector('[data-gallery-step="-1"]');
  const next = controls.querySelector('[data-gallery-step="1"]');
  let galleryFrame = 0;

  const updateControls = () => {
    galleryFrame = 0;
    previous.disabled = screenshotTrack.scrollLeft <= 2;
    next.disabled = screenshotTrack.scrollLeft >= screenshotTrack.scrollWidth - screenshotTrack.clientWidth - 2;
  };
  const scheduleControls = () => {
    if (!galleryFrame) galleryFrame = requestAnimationFrame(updateControls);
  };
  const slidePositions = () => {
    const start = links[0].getBoundingClientRect().left;
    return links.map((link) => link.getBoundingClientRect().left - start);
  };
  const scrollGallery = (left) => screenshotTrack.scrollTo({
    left,
    behavior: reducedMotion.matches ? "auto" : "smooth",
  });

  controls.hidden = false;
  controls.addEventListener("click", (event) => {
    const button = event.target.closest("[data-gallery-step]");
    if (!button || button.disabled) return;
    const positions = slidePositions();
    const target = Number(button.dataset.galleryStep) > 0
      ? positions.find((left) => left > screenshotTrack.scrollLeft + 2)
      : positions.reverse().find((left) => left < screenshotTrack.scrollLeft - 2);
    if (target !== undefined) scrollGallery(target);
  });
  screenshotTrack.addEventListener("scroll", scheduleControls, { passive: true });
  window.addEventListener("resize", scheduleControls);
  if ("ResizeObserver" in window) new ResizeObserver(scheduleControls).observe(screenshotTrack);
  screenshotTrack.addEventListener("keydown", (event) => {
    const index = links.indexOf(event.target.closest(".screenshot-link"));
    if (index < 0 || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const target = event.key === "Home" ? 0 : event.key === "End" ? links.length - 1
      : Math.max(0, Math.min(links.length - 1, index + (event.key === "ArrowRight" ? 1 : -1)));
    links[target].focus({ preventScroll: true });
    scrollGallery(slidePositions()[target]);
  });
  updateControls();

  const viewer = document.querySelector(".screenshot-dialog");
  if (viewer && typeof viewer.showModal === "function") {
    const viewerImage = viewer.querySelector(".viewer-image");
    const viewerTitle = viewer.querySelector("#viewer-title");
    const viewerStatus = viewer.querySelector(".viewer-status");
    const viewerPrevious = viewer.querySelector('[data-viewer-step="-1"]');
    const viewerNext = viewer.querySelector('[data-viewer-step="1"]');
    let activeIndex = 0;
    let requestID = 0;
    let opener;

    const showScreenshot = (index) => {
      activeIndex = index;
      const link = links[index];
      const thumbnail = link.querySelector("img");
      const request = ++requestID;
      viewerTitle.textContent = link.dataset.title;
      viewerImage.alt = thumbnail.alt;
      viewerImage.src = thumbnail.currentSrc || thumbnail.src;
      viewerImage.setAttribute("aria-busy", "true");
      viewerPrevious.disabled = index === 0;
      viewerNext.disabled = index === links.length - 1;
      viewerStatus.textContent = "불러오는 중";

      // A late image response must not replace a newer slide or a closed viewer.
      const fullImage = new Image();
      fullImage.onload = () => {
        if (request !== requestID || !viewer.open) return;
        viewerImage.src = fullImage.src;
        viewerImage.setAttribute("aria-busy", "false");
        viewerStatus.textContent = "";
      };
      fullImage.onerror = () => {
        if (request !== requestID || !viewer.open) return;
        viewerImage.setAttribute("aria-busy", "false");
        viewerStatus.textContent = "큰 이미지를 불러오지 못했습니다.";
      };
      fullImage.src = link.href;
    };

    links.forEach((link, index) => {
      link.setAttribute("aria-haspopup", "dialog");
      link.addEventListener("click", (event) => {
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        opener = link;
        viewer.showModal();
        document.documentElement.classList.add("screenshot-open");
        showScreenshot(index);
      });
    });
    viewer.querySelector(".viewer-close").addEventListener("click", () => viewer.close());
    const stepViewer = (step) => {
      const index = Math.max(0, Math.min(links.length - 1, activeIndex + step));
      if (index !== activeIndex) showScreenshot(index);
    };
    viewerPrevious.addEventListener("click", () => stepViewer(-1));
    viewerNext.addEventListener("click", () => stepViewer(1));
    const stage = viewer.querySelector(".viewer-stage");
    let swipe;
    const resetSwipe = () => { swipe = undefined; };
    stage.addEventListener("touchstart", (event) => {
      if (event.touches.length !== 1 || (window.visualViewport?.scale ?? 1) > 1) {
        resetSwipe();
        return;
      }
      const touch = event.touches[0];
      swipe = { id: touch.identifier, x: touch.clientX, y: touch.clientY };
    }, { passive: true });
    stage.addEventListener("touchmove", (event) => {
      if (!swipe) return;
      const touch = Array.from(event.touches).find((item) => item.identifier === swipe.id);
      if (event.touches.length !== 1 || !touch || Math.abs(touch.clientY - swipe.y) > 40) resetSwipe();
    }, { passive: true });
    stage.addEventListener("touchend", (event) => {
      if (!swipe) return;
      const touch = Array.from(event.changedTouches).find((item) => item.identifier === swipe.id);
      if (touch && event.touches.length === 0) {
        const dx = touch.clientX - swipe.x;
        const dy = touch.clientY - swipe.y;
        if (Math.abs(dx) >= 50 && Math.abs(dx) > Math.abs(dy) * 1.5) stepViewer(dx < 0 ? 1 : -1);
      }
      resetSwipe();
    }, { passive: true });
    stage.addEventListener("touchcancel", resetSwipe, { passive: true });
    viewer.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      stepViewer(event.key === "ArrowRight" ? 1 : -1);
    });
    viewer.addEventListener("close", () => {
      if (viewer.open) return;
      requestID++;
      resetSwipe();
      document.documentElement.classList.remove("screenshot-open");
      opener?.focus({ preventScroll: true });
    });
  }
}

const header = document.querySelector(".site-header");
const introMarker = document.querySelector(".intro .marker-rule");

if (header && introMarker) {
  // Keep the original in flow; the header copy takes over at the same screen position.
  const headerMarker = introMarker.cloneNode(true);
  headerMarker.classList.add("header-marker");
  headerMarker.hidden = true;
  header.append(headerMarker);

  let frame = 0;
  let needsMeasure = true;
  let geometry;
  let previousProgress;

  const updateMarker = () => {
    frame = 0;
    if (needsMeasure) {
      const markerBounds = introMarker.getBoundingClientRect();
      const headerBounds = header.getBoundingClientRect();
      geometry = {
        dockAt: markerBounds.top + window.scrollY - (headerBounds.top + header.clientHeight),
        left: markerBounds.left - headerBounds.left,
        width: markerBounds.width,
        height: markerBounds.height,
        fullWidth: headerBounds.width,
      };
      needsMeasure = false;
      previousProgress = undefined;
      headerMarker.style.height = `${geometry.height}px`;
    }

    const docked = window.scrollY >= geometry.dockAt;
    const progress = !docked ? -1 : reducedMotion.matches ? 1
      : Math.min(1, (window.scrollY - geometry.dockAt) / 200);
    if (progress === previousProgress) return;
    previousProgress = progress;

    introMarker.classList.toggle("is-docked", docked);
    headerMarker.hidden = !docked;
    if (!docked) return;

    const eased = progress * progress * (3 - 2 * progress);
    const left = geometry.left * (1 - eased);
    const width = geometry.width + (geometry.fullWidth - geometry.width) * eased;
    const height = geometry.height + (3 - geometry.height) * eased;
    headerMarker.style.transform = `translateX(${left}px) scale(${width / geometry.fullWidth}, ${height / geometry.height})`;
  };

  const scheduleUpdate = () => {
    if (!frame) frame = requestAnimationFrame(updateMarker);
  };
  const refreshGeometry = () => {
    needsMeasure = true;
    scheduleUpdate();
  };

  window.addEventListener("scroll", scheduleUpdate, { passive: true });
  window.addEventListener("resize", refreshGeometry);
  window.addEventListener("pageshow", refreshGeometry);
  window.addEventListener("load", refreshGeometry);
  reducedMotion.addEventListener("change", scheduleUpdate);

  if ("ResizeObserver" in window) {
    const observer = new ResizeObserver(refreshGeometry);
    [header, introMarker, introMarker.parentElement, introMarker.closest(".intro")]
      .forEach((element) => observer.observe(element));
  }
  if (document.fonts) document.fonts.ready.then(refreshGeometry);
  updateMarker();
}

if ("IntersectionObserver" in window && typeof Element.prototype.animate === "function") {
  const runningReveals = new Set();
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      observer.unobserve(entry.target);
      if (reducedMotion.matches) return;

      // Animate only on entry; content stays visible if JavaScript is unavailable.
      const animation = entry.target.animate([
        { opacity: 0, translate: "0 10px" },
        { opacity: 1, translate: "0 0" },
      ], {
        id: "section-reveal",
        duration: 420,
        easing: "cubic-bezier(0.22, 1, 0.36, 1)",
      });
      runningReveals.add(animation);
      animation.onfinish = animation.oncancel = () => runningReveals.delete(animation);
    });
  }, { threshold: 0.12 });

  document.querySelectorAll(".section-heading, .feature, .capability-item, .privacy-callout > *").forEach((element) => {
    if (element.getBoundingClientRect().top >= window.innerHeight) observer.observe(element);
  });

  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) runningReveals.forEach((animation) => animation.cancel());
  });
}
