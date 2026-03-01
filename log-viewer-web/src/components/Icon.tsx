interface IconEntry { ms: string; fill?: 1 }

const ICON_MAP: Record<string, IconEntry> = {
  // Status / circle-fill
  'bolt-circle-fill':        { ms: 'electric_bolt',       fill: 1 },
  'exclamation-circle-fill': { ms: 'error',               fill: 1 },
  'paperplane-circle-fill':  { ms: 'send',                fill: 1 },
  'link-circle-fill':        { ms: 'link',                fill: 1 },
  'arrows-circle-fill':      { ms: 'sync',                fill: 1 },
  'play-circle-fill':        { ms: 'play_circle',         fill: 1 },
  'refresh-circle-fill':     { ms: 'autorenew',           fill: 1 },
  'checkmark-circle-fill':   { ms: 'check_circle',        fill: 1 },
  'xmark-circle-fill':       { ms: 'cancel',              fill: 1 },
  'forward-circle-fill':     { ms: 'skip_next',           fill: 1 },
  'slash-circle-fill':       { ms: 'block',               fill: 1 },
  'stop-circle':             { ms: 'stop_circle',         fill: 1 },

  // Navigation
  'chevron-down':            { ms: 'expand_more'                   },
  'chevron-right':           { ms: 'chevron_right'                 },
  'chevron-left':            { ms: 'chevron_left'                  },
  'chevron-up':              { ms: 'expand_less'                   },
  'arrow-left':              { ms: 'arrow_back'                    },
  'arrow-right':             { ms: 'arrow_forward'                 },
  'arrow-right-circle':      { ms: 'arrow_circle_right', fill: 1  },

  // Workflow / blocks
  'clock':                   { ms: 'schedule'                      },
  'hourglass':               { ms: 'hourglass_empty'               },
  'repeat':                  { ms: 'repeat'                        },
  'branch':                  { ms: 'alt_route'                     },
  'rectangles-group':        { ms: 'grid_view'                     },
  'map-pin':                 { ms: 'location_on',        fill: 1  },
  'cpu':                     { ms: 'memory'                        },
  'house':                   { ms: 'home',               fill: 1  },
  'slider-horizontal':       { ms: 'tune'                          },
  'bolt':                    { ms: 'electric_bolt'                 },
  'sparkles':                { ms: 'auto_awesome',       fill: 1  },
  'doc-text':                { ms: 'description'                   },
  'folder':                  { ms: 'folder',             fill: 1  },
  'arrow-2-squarepath':      { ms: 'repeat'                        },
  'sun-max-fill':            { ms: 'light_mode',         fill: 1  },
  'arrow-triangle-branch':   { ms: 'alt_route'                     },
  'xmark-circle':            { ms: 'cancel'                        },
  'link':                    { ms: 'link'                           },
  'shield':                  { ms: 'shield',             fill: 1  },
  'square-stack':            { ms: 'stacks',             fill: 1  },

  // Workflow editor actions
  'checkmark-circle':        { ms: 'check_circle'                  },
  'questionmark-circle':     { ms: 'help_outline'                  },
  'plus-circle':             { ms: 'add_circle'                     },
  'plus-circle-fill':        { ms: 'add_circle',          fill: 1  },
  'line-3-horizontal':       { ms: 'drag_handle'                   },
  'arrow-up-arrow-down':     { ms: 'swap_vert'                     },
  'doc-on-doc':              { ms: 'content_copy'                  },
  'arrow-up-circle':         { ms: 'arrow_circle_up'               },

  // General UI
  'magnifying-glass':        { ms: 'search'                        },
  'sun':                     { ms: 'light_mode',         fill: 1  },
  'moon':                    { ms: 'dark_mode',          fill: 1  },
  'wifi':                    { ms: 'wifi'                          },
  'wifi-off':                { ms: 'wifi_off'                      },
  'gear':                    { ms: 'settings'                      },
  'exclamation-triangle':    { ms: 'warning',            fill: 1  },
  'copy':                    { ms: 'content_copy'                  },
  'spinner':                 { ms: 'progress_activity'             },
  'sidebar-left':            { ms: 'left_panel_close'              },
  'menu':                    { ms: 'menu'                          },
  'xmark':                   { ms: 'close'                         },
  'funnel':                  { ms: 'filter_alt',         fill: 1  },
  'filter':                  { ms: 'filter_list'                   },
  'pencil':                  { ms: 'edit'                           },
  'trash':                   { ms: 'delete'                        },
  'plus':                    { ms: 'add'                           },
  'eye':                     { ms: 'visibility'                    },
  'eye-slash':               { ms: 'visibility_off'                },

  // HomeKit services
  'hk-lightbulb':            { ms: 'lightbulb'                     },
  'hk-switch':               { ms: 'toggle_on',          fill: 1  },
  'hk-outlet':               { ms: 'electrical_services'           },
  'hk-fan':                  { ms: 'mode_fan'                      },
  'hk-thermostat':           { ms: 'thermostat'                    },
  'hk-garage':               { ms: 'garage',             fill: 1  },
  'hk-lock':                 { ms: 'lock',               fill: 1  },
  'hk-window-covering':      { ms: 'blinds'                        },
  'hk-motion':               { ms: 'motion_sensor_active', fill: 1 },
  'hk-occupancy':            { ms: 'person',             fill: 1  },
  'hk-temperature':          { ms: 'device_thermostat'             },
  'hk-humidity':             { ms: 'water_drop',         fill: 1  },
  'hk-contact':              { ms: 'sensor_door'                   },
  'hk-leak':                 { ms: 'water_damage',       fill: 1  },
  'hk-smoke':                { ms: 'detector_smoke',     fill: 1  },
  'hk-security':             { ms: 'security',           fill: 1  },
  'hk-camera':               { ms: 'videocam',           fill: 1  },
  'hk-tv':                   { ms: 'tv'                            },
  'hk-speaker':              { ms: 'speaker',            fill: 1  },
  'hk-valve':                { ms: 'valve'                         },
  'hk-doorbell':             { ms: 'doorbell',           fill: 1  },
  'hk-air-purifier':         { ms: 'air_purifier',       fill: 1  },
  'hk-air-quality':          { ms: 'air'                           },
  'hk-battery':              { ms: 'battery_full'                  },
  'hk-microphone':           { ms: 'mic',                fill: 1  },
  'hk-filter':               { ms: 'filter_alt',         fill: 1  },
  'hk-robot-vacuum':         { ms: 'robot_vacuum',       fill: 1  },
  'hk-blinds':               { ms: 'blinds_closed'                 },
  'hk-curtain':              { ms: 'curtains',           fill: 1  },
};

interface IconProps {
  name: string;
  size?: number;
  className?: string;
  style?: React.CSSProperties;
}

export function Icon({ name, size = 24, className = '', style }: IconProps) {
  const entry = ICON_MAP[name] ?? { ms: 'help_outline' };
  const fill = entry.fill ?? 0;
  const variationSettings = `'FILL' ${fill}, 'wght' 400, 'GRAD' 0, 'opsz' 24`;

  return (
    <span
      className={`material-symbols-rounded inline-flex items-center justify-center shrink-0 leading-none select-none ${className}`}
      style={{ fontSize: `${size}px`, fontVariationSettings: variationSettings, ...style }}
    >
      {entry.ms}
    </span>
  );
}
