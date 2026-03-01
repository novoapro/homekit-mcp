const CHARACTERISTIC_DISPLAY_NAMES: Record<string, string> = {
  '00000025-0000-1000-8000-0026BB765291': 'Power',
  '00000008-0000-1000-8000-0026BB765291': 'Brightness',
  '00000013-0000-1000-8000-0026BB765291': 'Hue',
  '0000002F-0000-1000-8000-0026BB765291': 'Saturation',
  '000000CE-0000-1000-8000-0026BB765291': 'Color Temperature',
  '00000011-0000-1000-8000-0026BB765291': 'Current Temperature',
  '00000035-0000-1000-8000-0026BB765291': 'Target Temperature',
  '00000036-0000-1000-8000-0026BB765291': 'Temperature Units',
  '0000000F-0000-1000-8000-0026BB765291': 'Current Mode',
  '00000033-0000-1000-8000-0026BB765291': 'Target Mode',
  '00000010-0000-1000-8000-0026BB765291': 'Current Humidity',
  '00000034-0000-1000-8000-0026BB765291': 'Target Humidity',
  '0000000E-0000-1000-8000-0026BB765291': 'Door State',
  '00000032-0000-1000-8000-0026BB765291': 'Target Door State',
  '0000001D-0000-1000-8000-0026BB765291': 'Lock State',
  '0000001E-0000-1000-8000-0026BB765291': 'Target Lock State',
  '0000006D-0000-1000-8000-0026BB765291': 'Current Position',
  '0000007C-0000-1000-8000-0026BB765291': 'Target Position',
  '00000072-0000-1000-8000-0026BB765291': 'Position State',
  '00000022-0000-1000-8000-0026BB765291': 'Motion Detected',
  '0000006A-0000-1000-8000-0026BB765291': 'Contact State',
  '00000071-0000-1000-8000-0026BB765291': 'Occupancy Detected',
  '00000076-0000-1000-8000-0026BB765291': 'Smoke Detected',
  '00000069-0000-1000-8000-0026BB765291': 'CO Detected',
  '00000068-0000-1000-8000-0026BB765291': 'Battery Level',
  '00000079-0000-1000-8000-0026BB765291': 'Low Battery',
  '0000008F-0000-1000-8000-0026BB765291': 'Charging State',
  '00000026-0000-1000-8000-0026BB765291': 'Outlet In Use',
  '00000029-0000-1000-8000-0026BB765291': 'Rotation Speed',
  '000000AF-0000-1000-8000-0026BB765291': 'Fan State',
  '000000BF-0000-1000-8000-0026BB765291': 'Target Fan State',
  '000000B0-0000-1000-8000-0026BB765291': 'Active',
  '00000075-0000-1000-8000-0026BB765291': 'Status Active',
  '00000023-0000-1000-8000-0026BB765291': 'Name',
  '00000024-0000-1000-8000-0026BB765291': 'Obstruction Detected',
  '00000077-0000-1000-8000-0026BB765291': 'Fault',
  '0000007A-0000-1000-8000-0026BB765291': 'Tampered',
  '0000006B-0000-1000-8000-0026BB765291': 'Light Level',
  '00000073-0000-1000-8000-0026BB765291': 'Input Event',
  '000000D1-0000-1000-8000-0026BB765291': 'Program Mode',
  '000000D2-0000-1000-8000-0026BB765291': 'In Use',
  '000000D4-0000-1000-8000-0026BB765291': 'Remaining Duration',
  '000000D3-0000-1000-8000-0026BB765291': 'Set Duration',
  '000000D5-0000-1000-8000-0026BB765291': 'Valve Type',
  '000000D6-0000-1000-8000-0026BB765291': 'Is Configured',
};

const BOOLEAN_TYPES = new Set([
  'Power', 'Motion Detected', 'Contact State', 'Occupancy Detected',
  'Smoke Detected', 'CO Detected', 'Outlet In Use', 'Obstruction Detected',
  'Status Active', 'Active',
]);

const PERCENTAGE_TYPES = new Set([
  'Brightness', 'Saturation', 'Battery Level',
  'Current Humidity', 'Target Humidity',
  'Current Position', 'Target Position', 'Rotation Speed',
]);

const TEMPERATURE_TYPES = new Set(['Current Temperature', 'Target Temperature']);

const DOOR_STATES = ['Open', 'Closed', 'Opening', 'Closing', 'Stopped'];
const LOCK_STATES = ['Unsecured', 'Secured', 'Jammed', 'Unknown'];

export function characteristicDisplayName(type: string): string {
  const upper = type.toUpperCase();
  if (CHARACTERISTIC_DISPLAY_NAMES[upper]) {
    return CHARACTERISTIC_DISPLAY_NAMES[upper];
  }
  for (const [key, value] of Object.entries(CHARACTERISTIC_DISPLAY_NAMES)) {
    if (key.toUpperCase() === upper) return value;
  }
  if (!/^[0-9A-F]{8}-[0-9A-F]{4}-/i.test(type)) {
    return type
      .replace(/[-_.]/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase())
      .trim();
  }
  return type;
}

export function formatCharacteristicValue(value: unknown, characteristicType: string): string {
  if (value === undefined || value === null) return '--';

  const name = characteristicDisplayName(characteristicType);

  if (BOOLEAN_TYPES.has(name)) {
    if (typeof value === 'boolean') return value ? 'On' : 'Off';
    if (typeof value === 'number') return value !== 0 ? 'On' : 'Off';
  }

  if (PERCENTAGE_TYPES.has(name)) {
    return `${value}%`;
  }

  if (TEMPERATURE_TYPES.has(name)) {
    if (typeof value === 'number') return `${value.toFixed(1)}\u00B0C`;
  }

  if (name === 'Hue') return `${value}\u00B0`;
  if (name === 'Color Temperature') return `${value}K`;

  if (name === 'Door State' && typeof value === 'number') {
    return DOOR_STATES[value] ?? String(value);
  }

  if (name === 'Lock State' && typeof value === 'number') {
    return LOCK_STATES[value] ?? String(value);
  }

  if (typeof value === 'boolean') return value ? 'On' : 'Off';
  return String(value);
}
