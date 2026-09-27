// Navigation and the hero route tracer. No build step, no dependencies.
(function () {
  "use strict";

  document.documentElement.classList.add("js");

  // Mobile navigation
  var header = document.querySelector(".masthead");
  var toggle = document.querySelector(".nav-toggle");
  if (header && toggle) {
    var setOpen = function (open) {
      header.setAttribute("data-open", String(open));
      toggle.setAttribute("aria-expanded", String(open));
    };
    toggle.addEventListener("click", function () {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });
    header.addEventListener("click", function (event) {
      if (event.target.closest(".nav a")) setOpen(false);
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
        setOpen(false);
        toggle.focus();
      }
    });
  }

  // Route map: inlay on load, then trace a route from the legend
  var route = document.querySelector(".route");
  if (!route) return;

  requestAnimationFrame(function () {
    route.classList.add("is-inlaid");
  });

  var chips = route.querySelectorAll(".chip");
  var pinned = null;

  var show = function (name) {
    if (name) route.setAttribute("data-trace", name);
    else route.removeAttribute("data-trace");
  };

  chips.forEach(function (chip) {
    var name = chip.getAttribute("data-route");
    chip.addEventListener("mouseenter", function () { show(name); });
    chip.addEventListener("mouseleave", function () { show(pinned); });
    chip.addEventListener("focus", function () { show(name); });
    chip.addEventListener("blur", function () { show(pinned); });
    chip.addEventListener("click", function () {
      pinned = pinned === name ? null : name;
      chips.forEach(function (other) {
        other.setAttribute("aria-pressed", String(other.getAttribute("data-route") === pinned));
      });
      show(pinned);
    });
  });
})();
