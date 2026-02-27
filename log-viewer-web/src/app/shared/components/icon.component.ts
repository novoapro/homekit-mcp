import { Component, input, computed } from '@angular/core';

interface IconEntry { ms: string; fill?: 1 }

const ICON_MAP: Record<string, IconEntry> = {
  // ── Status / circle-fill ──────────────────────────────
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

  // ── Navigation ────────────────────────────────────────
  'chevron-down':            { ms: 'expand_more'                   },
  'chevron-right':           { ms: 'chevron_right'                 },
  'chevron-up':              { ms: 'expand_less'                   },
  'arrow-right':             { ms: 'arrow_forward'                 },
  'arrow-right-circle':      { ms: 'arrow_circle_right', fill: 1  },

  // ── Workflow / blocks ─────────────────────────────────
  'clock':                   { ms: 'schedule'                      },
  'hourglass':               { ms: 'hourglass_empty'               },
  'repeat':                  { ms: 'repeat'                        },
  'branch':                  { ms: 'alt_route'                     },
  'rectangles-group':        { ms: 'grid_view'                     },
  'map-pin':                 { ms: 'location_on',        fill: 1  },
  'cpu':                     { ms: 'memory'                        },
  'house':                   { ms: 'home',               fill: 1  },
  'slider-horizontal':       { ms: 'tune'                          },

  // ── General UI ────────────────────────────────────────
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
  'trash':                   { ms: 'delete'                        },
  'plus':                    { ms: 'add'                           },
  'eye':                     { ms: 'visibility'                    },
  'eye-slash':               { ms: 'visibility_off'                },

  // ── HomeKit services ──────────────────────────────────
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

@Component({
  selector: 'app-icon',
  standalone: true,
  template: `
    <span class="material-symbols-rounded"
          [style.font-size.px]="size()"
          [style.font-variation-settings]="variationSettings()">{{ iconName() }}</span>
  `,
  styles: [`
    :host {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .material-symbols-rounded {
      display: block;
      line-height: 1;
      user-select: none;
    }
  `]
})
export class IconComponent {
  name = input.required<string>();
  size = input(24);

  private readonly entry = computed(() => ICON_MAP[this.name()] ?? { ms: 'help_outline' });

  readonly iconName = computed(() => this.entry().ms);

  readonly variationSettings = computed(() => {
    const fill = this.entry().fill ?? 0;
    return `'FILL' ${fill}, 'wght' 400, 'GRAD' 0, 'opsz' 24`;
  });
}
