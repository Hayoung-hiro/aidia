// Summaries reflect the bound input values, including server-driven resets.
$(function () {
  function updateSummary(span, value) {
    var input = document.getElementById(span.dataset.detailInput);
    if (!input) return;
    if (value === undefined) value = input.type === 'checkbox' ? input.checked : $(input).val();
    if (input.tagName === 'SELECT') {
      var option = Array.from(input.options).find(function (item) { return item.value === String(value); });
      value = option ? option.text : value;
    }
    if (typeof value === 'boolean') value = value ? 'On' : 'Off';
    span.textContent = (value === null || value === '' ? '\u2014' : value) + (span.dataset.detailSuffix || '');
  }
  document.querySelectorAll('[data-detail-input]').forEach(function (span) { updateSummary(span); });
  $(document).on('shiny:inputchanged', function (event) {
    document.querySelectorAll('[data-detail-input]').forEach(function (span) {
      if (span.dataset.detailInput === event.name) updateSummary(span, event.value);
    });
  });
});
