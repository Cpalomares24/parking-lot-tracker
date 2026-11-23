// ParkSmart front-end demo. No server or database required.
const hourSelect = document.getElementById('hourSelect');
const sortSelect = document.getElementById('sortSelect');
const searchInput = document.getElementById('search');
const garageGrid = document.getElementById('garageGrid');
const hourChart = document.getElementById('hourChart');
const typeSelect = document.getElementById('typeSelect');
const paymentSelect = document.getElementById('paymentSelect');
const statusSelect = document.getElementById('statusSelect');

function formatHour(hour) { return `${hour % 12 || 12}:00 ${hour < 12 ? 'AM' : 'PM'}`; }
function statusFor(percent) {
  if (percent >= 60) return {label:'Plenty of space', cls:'green'};
  if (percent >= 30) return {label:'Moderate', cls:'amber'};
  return {label:'Usually busy', cls:'red'};
}
function estimatedDemoPercent(garage, hour) {
  // Illustrative adjustment only, NOT an actual per-garage historical prediction.
  const baseline = PARKSMART_HOURLY.find(row => row.hour === 14).available;
  const current = PARKSMART_HOURLY.find(row => row.hour === hour).available;
  return Math.max(2, Math.min(98, Math.round(garage.availabilityAt14 + current - baseline)));
}
function renderGarages() {
  const hour = Number(hourSelect.value);
  const term = searchInput.value.trim().toLowerCase();
  const garages = PARKSMART_GARAGES.filter(g => {
    const matchesSearch = [g.name,g.code,g.area,g.parkingType,g.payment].some(s => s.toLowerCase().includes(term));
    const matchesType = typeSelect.value === 'all' || g.parkingType === typeSelect.value;
    const matchesPayment = paymentSelect.value === 'all' || g.payment === paymentSelect.value;
    const availability = estimatedDemoPercent(g,hour);
    const matchesStatus = statusSelect.value === 'all' || (statusSelect.value === 'high' && availability >= 60) || (statusSelect.value === 'moderate' && availability >= 30 && availability < 60) || (statusSelect.value === 'busy' && availability < 30);
    return matchesSearch && matchesType && matchesPayment && matchesStatus;
  });
  garages.sort((a,b) => sortSelect.value === 'name' ? a.name.localeCompare(b.name) : sortSelect.value === 'busy' ? estimatedDemoPercent(a,hour)-estimatedDemoPercent(b,hour) : estimatedDemoPercent(b,hour)-estimatedDemoPercent(a,hour));
  document.getElementById('locationCount').textContent = garages.length;
  document.getElementById('resultsLabel').textContent = `${garages.length} of ${PARKSMART_GARAGES.length} locations shown`;
  document.getElementById('hourAverage').textContent = PARKSMART_HOURLY.find(row=>row.hour===hour).available.toFixed(2)+'%';
  document.getElementById('selectedHourLabel').textContent = `At ${formatHour(hour)} · historical`;
  garageGrid.innerHTML = garages.length ? garages.map(g => {
    const pct = estimatedDemoPercent(g,hour), status = statusFor(pct);
    return `<article class="garage-card"><div class="garage-top"><span class="garage-symbol">P</span><span class="status ${status.cls}">${status.label}</span></div><h3>${g.name}</h3><p class="garage-area">${g.area} · ${g.code}</p><div class="garage-tags"><span>${g.parkingType === 'general' ? 'General parking' : g.parkingType === 'permit' ? 'Permit parking' : 'Reserved parking'}</span><span>${g.payment === 'paid' ? 'Paid' : 'Free'}</span></div><div class="garage-percent">${pct}% <span>available</span></div><div class="progress"><div class="progress-fill ${status.cls}" style="width:${pct}%"></div></div><div class="garage-bottom"><span>Capacity: ${g.capacity} spaces</span><span>Demo estimate</span></div><button type="button" class="details-button" data-garage-id="${g.id}" aria-label="View details for ${g.name}">View details <span aria-hidden="true">↗</span></button></article>`;
  }).join('') : '<p class="empty">No garages match your search.</p>';
  renderChart(hour);
}
function renderChart(selectedHour) {
  hourChart.innerHTML = PARKSMART_HOURLY.map(row => `<div class="chart-column"><span class="chart-value">${row.hour===selectedHour?row.available.toFixed(1)+'%':''}</span><div class="chart-bar ${row.hour===selectedHour?'active':''}" style="height:${row.available}%" title="${formatHour(row.hour)}: ${row.available}% available"></div><span class="chart-hour">${row.hour%12||12}${row.hour<12?'a':'p'}</span></div>`).join('');
}
PARKSMART_HOURLY.forEach(row => { const option = document.createElement('option'); option.value=row.hour; option.textContent=formatHour(row.hour); option.selected=row.hour===14; hourSelect.appendChild(option); });
[hourSelect,sortSelect,typeSelect,paymentSelect,statusSelect].forEach(el=>el.addEventListener('change',renderGarages));
searchInput.addEventListener('input',renderGarages);
document.getElementById('resetFilters').addEventListener('click', () => {
  searchInput.value = '';
  typeSelect.value = 'all';
  paymentSelect.value = 'all';
  statusSelect.value = 'all';
  sortSelect.value = 'available';
  renderGarages();
});
renderGarages();

// Accessible garage-details popup. The original garage filters continue to work.
const garageDialog = document.getElementById('garageDialog');
const closeDialogButton = document.getElementById('closeDialog');
let previousFocus = null;

function showGarageDetails(garage) {
  const hour = Number(hourSelect.value);
  const pct = estimatedDemoPercent(garage, hour);
  const status = statusFor(pct);
  previousFocus = document.activeElement;
  document.getElementById('dialogTitle').textContent = garage.name;
  document.getElementById('dialogArea').textContent = `${garage.area} · ${garage.code}`;
  document.getElementById('dialogStatus').innerHTML = `<span class="status ${status.cls}">${status.label}</span>`;
  document.getElementById('dialogPercent').textContent = `${pct}%`;
  document.getElementById('dialogCapacity').textContent = `${garage.capacity} spaces`;
  // Demo estimate: round the available percentage times total capacity.
  document.getElementById('dialogFreeSpaces').textContent = `${Math.round(garage.capacity * pct / 100)} spaces`;
  document.getElementById('dialogHour').textContent = formatHour(hour);
  document.getElementById('dialogFill').style.width = `${pct}%`;
  document.getElementById('dialogFill').className = `progress-fill ${status.cls}`;
  const fields = [
    ['Parking type', garage.parkingType === 'general' ? 'General parking' : garage.parkingType === 'permit' ? 'Permit parking' : 'Reserved parking'],
    ['Payment', garage.payment === 'paid' ? 'Paid parking' : 'Free parking'],
    ['Location code', garage.code],
    ['Data source', 'Demonstration garage']
  ];
  const attributes = document.getElementById('dialogAttributes');
  attributes.replaceChildren();
  fields.forEach(([label, value]) => {
    const cell = document.createElement('div');
    const small = document.createElement('small'); small.textContent = label;
    const strong = document.createElement('strong'); strong.textContent = value;
    cell.append(small, strong); attributes.appendChild(cell);
  });
  document.getElementById('dialogChart').innerHTML = PARKSMART_HOURLY.map(row => {
    const value = estimatedDemoPercent(garage, row.hour);
    return `<div class="dialog-bar-group" title="${formatHour(row.hour)}: ${value}% available (demo)"><span class="dialog-bar-value">${row.hour === hour ? value + '%' : ''}</span><div class="dialog-bar ${row.hour === hour ? 'selected' : ''}" style="height:${value}%"></div><span class="dialog-bar-hour">${row.hour % 12 || 12}${row.hour < 12 ? 'a' : 'p'}</span></div>`;
  }).join('');
  garageDialog.showModal();
  closeDialogButton.focus();
}

garageGrid.addEventListener('click', event => {
  const button = event.target.closest('[data-garage-id]');
  if (!button) return;
  const garage = PARKSMART_GARAGES.find(g => g.id === button.dataset.garageId);
  if (garage) showGarageDetails(garage);
});
closeDialogButton.addEventListener('click', () => garageDialog.close());
garageDialog.addEventListener('click', event => {
  // Close when clicking the dimmed backdrop, not the dialog content.
  if (event.target === garageDialog) garageDialog.close();
});
garageDialog.addEventListener('close', () => previousFocus?.focus());
