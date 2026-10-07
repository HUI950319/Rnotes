(() => {
  const directory = document.getElementById("note-directory");
  const filters = document.getElementById("note-filters");
  if (!directory || !filters) return;

  const rows = Array.from(directory.querySelectorAll("tbody tr"));
  const packageSelect = document.getElementById("note-package");
  const topicSelect = document.getElementById("note-topic");
  const queryInput = document.getElementById("note-query");
  const result = document.getElementById("note-count");
  const empty = document.getElementById("note-empty");
  const entries = rows.map((row) => ({
    row,
    package: row.cells[0].textContent.trim(),
    topic: row.cells[2].textContent.trim(),
    text: row.textContent.toLocaleLowerCase(),
  }));

  for (const [select, field] of [[packageSelect, "package"], [topicSelect, "topic"]]) {
    for (const value of [...new Set(entries.map((entry) => entry[field]))]) {
      select.add(new Option(value, value));
    }
  }

  const update = () => {
    const words = queryInput.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    let count = 0;
    for (const entry of entries) {
      const visible = (!packageSelect.value || entry.package === packageSelect.value)
        && (!topicSelect.value || entry.topic === topicSelect.value)
        && words.every((word) => entry.text.includes(word));
      entry.row.hidden = !visible;
      if (visible) count++;
    }
    result.textContent = `显示 ${count} / ${entries.length} 篇笔记`;
    empty.hidden = count > 0;
  };

  packageSelect.addEventListener("change", update);
  topicSelect.addEventListener("change", update);
  queryInput.addEventListener("input", update);
  document.getElementById("note-reset").addEventListener("click", () => {
    packageSelect.value = "";
    topicSelect.value = "";
    queryInput.value = "";
    update();
    queryInput.focus();
  });
  filters.hidden = false;
  update();
})();
