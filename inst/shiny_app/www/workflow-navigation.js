// Route sidebar clicks through the same prerequisite checks as Next.
document.addEventListener('click', function (event) {
  // Shiny's tab binding may activate tabs programmatically after server approval.
  if (!event.isTrusted) return;
  var link = event.target.closest('.main-sidebar a[data-value]');
  if (!link || !['data', 'setup', 'results'].includes(link.dataset.value)) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  Shiny.setInputValue('workflow_navigate', link.dataset.value, {priority: 'event'});
}, true);
$(function () {
  Shiny.addCustomMessageHandler('workflow-validation', function (message) {
    document.querySelectorAll('.workflow-field-error[data-validation-scope="' + message.scope + '"]').forEach(function (error) {
      var field = document.getElementById(error.dataset.field);
      if (field) {
        field.removeAttribute('aria-invalid');
        var described = (field.getAttribute('aria-describedby') || '').split(' ').filter(function (id) { return id && id !== error.id; });
        if (described.length) field.setAttribute('aria-describedby', described.join(' '));
        else field.removeAttribute('aria-describedby');
        var container = field.closest('.shiny-input-container');
        if (container) container.classList.remove('workflow-has-error');
      }
      error.remove();
    });
    Object.entries(message.issues || {}).forEach(function (entry) {
      var field = document.getElementById(entry[0]);
      if (!field) return;
      var container = field.closest('.shiny-input-container');
      var row = field.closest('.config-row');
      var error = document.createElement('div');
      error.id = 'workflow-error-' + entry[0];
      error.className = 'workflow-field-error';
      error.dataset.validationScope = message.scope;
      error.dataset.field = entry[0];
      error.setAttribute('role', 'alert');
      error.textContent = entry[1];
      (row || container || field.parentElement).appendChild(error);
      field.setAttribute('aria-invalid', 'true');
      field.setAttribute('aria-describedby', ((field.getAttribute('aria-describedby') || '') + ' ' + error.id).trim());
      if (container) container.classList.add('workflow-has-error');
    });
  });
  Shiny.addCustomMessageHandler('workflow-focus', function (id) {
    var panel = document.getElementById(id);
    if (panel) {
      for (var ancestor = panel.parentElement; ancestor; ancestor = ancestor.parentElement) {
        if (ancestor.tagName === 'DETAILS') ancestor.open = true;
      }
      requestAnimationFrame(function () {
        var container = panel.closest('.shiny-input-container');
        var focus = panel;
        if (!focus.getBoundingClientRect().height && container)
          focus = container.querySelector('.selectize-input, .irs-handle, .btn-file') || container;
        if (!focus.hasAttribute('tabindex') && !focus.matches('input, select, button')) focus.tabIndex = -1;
        (container || panel).scrollIntoView({block: 'center'});
        focus.focus({preventScroll: true});
      });
    }
  });
});
