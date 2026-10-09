// Quarto's collapse anchors have no href, so explicitly support keyboard use.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll('#quarto-sidebar a[data-bs-toggle="collapse"]:not([href])').forEach(toggle => {
    toggle.setAttribute("role", "button");
    toggle.setAttribute("tabindex", "0");
    toggle.setAttribute("aria-controls", toggle.dataset.bsTarget.slice(1));
    toggle.addEventListener("keydown", event => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        toggle.click();
      }
    });
  });
});
