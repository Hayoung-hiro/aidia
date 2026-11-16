// A native range input over Shiny's plot panel keeps dragging local and smooth.
// Commit to the existing controls on release, so preview/confirm/reset share
// the same settings and validation as numeric entry.
(function () {
  $(function () {
    var control = document.getElementById('fz_boundary_control');
    if (!control) return;
    var plot = document.getElementById('fz_validation_plot');
    var slider = document.getElementById('fz_boundary_drag');
    var status = control.querySelector('.fz-boundary-status');
    var valueLabel = control.querySelector('.fz-boundary-value');
    var qualityLabel = control.querySelector('.fz-boundary-quality');
    var breakdown = control.querySelector('.fz-boundary-breakdown');
    var bands = control.querySelector('.fz-boundary-bands');
    var profile = null;
    var geometry = null;
    var coordmap = null;
    var dragging = false;
    var min = Number(slider.min);
    var max = Number(slider.max);

    function lowerBound(values, value) {
      var lo = 0, hi = values.length;
      while (lo < hi) {
        var mid = Math.floor((lo + hi) / 2);
        if (values[mid] < value) lo = mid + 1;
        else hi = mid;
      }
      return lo;
    }

    function countBand(values, value, margin) {
      var total = 0;
      // Three periodic copies also handle the 0 / I seam without edge bias.
      [-profile.increment, 0, profile.increment].forEach(function (shift) {
        total += lowerBound(values, value + margin - shift + 1e-10) -
          lowerBound(values, value - margin - shift - 1e-10);
      });
      return total;
    }

    function selectedMargin() {
      return Number(document.getElementById('fz_margin').value);
    }

    function drawBand(value, margin) {
      bands.replaceChildren();
      if (!geometry || !profile) return;
      [-profile.increment, 0, profile.increment].forEach(function (shift) {
        var lo = Math.max(0, value - margin + shift);
        var hi = Math.min(profile.increment, value + margin + shift);
        if (hi <= lo) return;
        var band = document.createElement('span');
        band.style.left = (geometry.left + (lo - geometry.domainLeft) * geometry.pixelsPerUnit) + 'px';
        band.style.top = geometry.top + 'px';
        band.style.width = (hi - lo) * geometry.pixelsPerUnit + 'px';
        band.style.height = geometry.height + 'px';
        bands.appendChild(band);
      });
    }

    function selectedOffset() {
      var preset = document.getElementById('fz_offset_preset').value;
      return Number(preset === 'custom' ? document.getElementById('custom_fz_offset').value : preset);
    }

    function showValue() {
      var value = Number(slider.value);
      valueLabel.textContent = 'FZ offset = ' + value.toFixed(4);
      slider.setAttribute('aria-valuetext', value.toFixed(4));
      if (!profile) return;
      var margin = selectedMargin();
      var target = document.getElementById('fz_target').value;
      var allCount = 0, allN = 0, targetCount = 0, targetN = 0;
      var details = profile.groups.map(function (group) {
        var count = countBand(group.phase, value, margin);
        allCount += count;
        allN += group.n;
        if (target === 'all' || group.label === '2+') {
          targetCount += count;
          targetN += group.n;
        }
        return group.label + ': ' + count.toLocaleString() + '/' + group.n.toLocaleString();
      });
      var percent = targetN ? (100 * targetCount / targetN).toFixed(2) : '0.00';
      qualityLabel.textContent = targetCount.toLocaleString() + ' / ' + targetN.toLocaleString() +
        ' (' + percent + '%) within \u00b1' + margin.toFixed(3) + ' m/z';
      breakdown.textContent = 'In band \u2014 All: ' + allCount.toLocaleString() + '/' + allN.toLocaleString() +
        ' | ' + details.join(' | ');
      drawBand(value, margin);
    }

    function positionSlider() {
      var img = plot.querySelector('img');
      var value = selectedOffset();
      var valid = Number.isFinite(value) && value >= min && value <= max;
      var margin = selectedMargin();
      valid = valid && margin >= .001 && margin <= .25;
      var hasTarget = profile && profile.groups.some(function (group) {
        return group.n && (document.getElementById('fz_target').value === 'all' || group.label === '2+');
      });
      var panel = coordmap && coordmap.panels && coordmap.panels[0];
      if (!img || !img.complete || !panel || !hasTarget || !valid || !img.clientWidth) {
        slider.style.display = 'none';
        slider.disabled = true;
        status.style.display = 'none';
        breakdown.textContent = '';
        bands.replaceChildren();
        geometry = null;
        return;
      }
      var imageRect = img.getBoundingClientRect();
      var canvasRect = control.querySelector('.fz-boundary-canvas').getBoundingClientRect();
      var scaleX = imageRect.width / coordmap.dims.width;
      var scaleY = imageRect.height / coordmap.dims.height;
      var domain = panel.domain;
      var range = panel.range;
      var pixelsPerUnit = (range.right - range.left) / (domain.right - domain.left);
      var left = (range.left + (min - domain.left) * pixelsPerUnit) * scaleX;
      var width = (max - min) * pixelsPerUnit * scaleX;
      var height = (range.bottom - range.top) * scaleY;
      geometry = {left: imageRect.left - canvasRect.left + range.left * scaleX,
        top: imageRect.top - canvasRect.top + range.top * scaleY,
        domainLeft: domain.left, pixelsPerUnit: pixelsPerUnit * scaleX, height: height};
      // Range thumbs travel within the input's width minus their own width.
      // Extend by half the 24px thumb on each side to align its centre exactly.
      slider.style.left = (imageRect.left - canvasRect.left + left - 12) + 'px';
      slider.style.top = (imageRect.top - canvasRect.top + range.top * scaleY) + 'px';
      slider.style.width = (width + 24) + 'px';
      slider.style.height = height + 'px';
      slider.style.setProperty('--fz-handle-height', height + 'px');
      slider.style.display = 'block';
      slider.disabled = false;
      status.style.display = 'flex';
      if (!dragging) slider.value = value;
      showValue();
    }

    Shiny.addCustomMessageHandler('aidia:fz-profile', function (message) {
      profile = message.profile;
      if (profile) profile.groups.forEach(function (group) {
        if (!Array.isArray(group.phase)) group.phase = [group.phase];
      });
      positionSlider();
    });
    Shiny.addCustomMessageHandler('aidia:fz-suggestion-enabled', function (message) {
      document.getElementById('fz_apply_suggestion').disabled = !message.enabled;
    });
    $(document).on('shiny:value', function (event) {
      if (event.name !== 'fz_validation_plot') return;
      coordmap = event.value && event.value.coordmap;
      requestAnimationFrame(positionSlider);
    });
    // Image load and resize both matter: plot coordinates use image pixels,
    // which can differ from CSS pixels on high-DPI or resized displays.
    plot.addEventListener('load', positionSlider, true);
    new ResizeObserver(positionSlider).observe(plot);
    $(document).on('change', '#fz_offset_preset, #custom_fz_offset, #fz_target, #fz_margin', positionSlider);

    slider.addEventListener('pointerdown', function () { dragging = true; });
    slider.addEventListener('input', showValue);
    slider.addEventListener('change', function () {
      var value = Number(slider.value);
      if (!Number.isFinite(value) || slider.disabled) return;
      var numeric = document.getElementById('custom_fz_offset');
      var preset = document.getElementById('fz_offset_preset');
      numeric.value = value.toFixed(4);
      // Send both controls in the same Shiny input batch, avoiding a preview
      // with the previous custom value during the switch from a preset.
      $(numeric).trigger('change');
      if (preset.selectize) preset.selectize.setValue('custom');
      else $(preset).val('custom').trigger('change');
      dragging = false;
      positionSlider();
    });
    document.addEventListener('pointerup', function () {
      if (!dragging) return;
      dragging = false;
      requestAnimationFrame(positionSlider);
    });
    slider.addEventListener('pointercancel', function () {
      dragging = false;
      positionSlider();
    });
  });
})();
