// File selection starts feedback immediately; only server validation marks it ready.
$(function () {
  var labels = {
    parquet_file: {empty: 'Required \u00b7 Choose a report', queued: 'Report selected \u00b7 Click Compute', ready: 'Report computed'},
    ms1_files: {empty: 'Required \u00b7 Add feature files', queued: 'Features selected \u00b7 Click Compute', ready: 'Features computed'},
    method_file: {empty: 'Optional \u00b7 No template loaded', ready: 'Template loaded \u00b7 Settings imported'}
  };
  function setState(id, state) {
    if (!labels[id] || !['empty', 'queued', 'reading', 'ready', 'error'].includes(state)) return;
    var card = document.querySelector('[data-upload-input="' + id + '"]');
    if (!card) return;
    card.dataset.uploadState = state;
    card.setAttribute('aria-busy', state === 'reading' ? 'true' : 'false');
    card.querySelector('.workflow-upload-icon').textContent =
      {empty: '\u25cb', queued: '\u25cb', reading: '\u21bb', ready: '\u2713', error: '!'}[state];
    card.querySelector('.workflow-upload-label').textContent =
      state === 'reading' ? 'Uploading and reading\u2026' :
      state === 'error' ? 'Could not load file' : labels[id][state];
  }
  $(document).on('change', '#parquet_file, #ms1_files, #method_file', function () {
    if (this.files && this.files.length) setState(this.id, 'reading');
  });
  Shiny.addCustomMessageHandler('workflow-upload-state', function (message) {
    setState(message.id, message.state);
  });
});
