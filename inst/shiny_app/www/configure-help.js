// Place contextual help within the viewport, including on narrow screens.
(function () {
  function closeHelp(except) {
    document.querySelectorAll('.config-help[open]').forEach(function (help) {
      if (help !== except) help.open = false;
    });
  }

  function positionHelp(help) {
    var anchor = help.querySelector('summary').getBoundingClientRect();
    var panel = help.querySelector('.config-help-body');
    panel.style.left = Math.max(12, Math.min(anchor.left, window.innerWidth - panel.offsetWidth - 12)) + 'px';
    panel.style.top = Math.max(12, Math.min(anchor.bottom + 8, window.innerHeight - panel.offsetHeight - 12)) + 'px';
  }

  // Shiny can insert explanation images after the disclosure opens.
  var panelResize = new ResizeObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.target.parentElement.open) positionHelp(entry.target.parentElement);
    });
  });

  document.addEventListener('toggle', function (event) {
    var help = event.target;
    if (!help.matches('.config-help') || !help.open) return;
    closeHelp(help);
    positionHelp(help);
    panelResize.observe(help.querySelector('.config-help-body'));
  }, true);

  document.addEventListener('click', function (event) {
    if (!event.target.closest('.config-help')) closeHelp();
  });
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    var help = document.querySelector('.config-help[open]');
    if (help) {
      help.open = false;
      help.querySelector('summary').focus();
      event.preventDefault();
    }
  });
  window.addEventListener('resize', function () { closeHelp(); });
  window.addEventListener('scroll', function () {
    document.querySelectorAll('.config-help[open]').forEach(positionHelp);
  });
})();
