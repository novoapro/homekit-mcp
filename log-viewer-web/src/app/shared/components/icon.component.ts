import { Component, input } from '@angular/core';

@Component({
  selector: 'app-icon',
  standalone: true,
  template: `
    <svg [attr.width]="size()" [attr.height]="size()" viewBox="0 0 24 24" fill="currentColor">
      @switch (name()) {
        @case ('bolt-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <path d="M13.5 4L8 13h3.5L10 20l6-9h-3.5L13.5 4z"/>
        }
        @case ('exclamation-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M12 7v6M12 15.5v1" stroke="white" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('paperplane-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M5 12l2.5 1.5L12 11l-3 4 6.5 2.5L19 5 5 12z" fill="white"/>
        }
        @case ('link-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M10 13a3 3 0 0 0 4.24.01l1.5-1.5a3 3 0 0 0-4.24-4.24l-.88.87M14 11a3 3 0 0 0-4.24-.01l-1.5 1.5a3 3 0 0 0 4.24 4.24l.88-.87" stroke="white" stroke-width="1.5" stroke-linecap="round" fill="none"/>
        }
        @case ('arrows-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M7 12h10M14 9l3 3-3 3M10 15l-3-3 3-3" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('play-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M10 8l6 4-6 4V8z" fill="white"/>
        }
        @case ('refresh-circle-fill') {
          <circle cx="12" cy="12" r="11" opacity="0.15" fill="currentColor"/>
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M16 12a4 4 0 0 1-7.46 2M8 12a4 4 0 0 1 7.46-2" stroke="white" stroke-width="1.5" stroke-linecap="round" fill="none"/>
          <path d="M16 9v3h-3M8 15v-3h3" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('checkmark-circle-fill') {
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M8 12l2.5 3L16 9" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('xmark-circle-fill') {
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M9 9l6 6M15 9l-6 6" stroke="white" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('forward-circle-fill') {
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M8 8l4 4-4 4M12 8l4 4-4 4" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('slash-circle-fill') {
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <path d="M6 18L18 6" stroke="white" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('chevron-down') {
          <path d="M6 9l6 6 6-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('chevron-right') {
          <path d="M9 6l6 6-6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('clock') {
          <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M12 7v5l3 3" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('hourglass') {
          <path d="M7 4h10M7 20h10M7 4v4a5 5 0 0 0 5 5 5 5 0 0 0 5-5V4M7 20v-4a5 5 0 0 1 5-5 5 5 0 0 1 5 5v4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('repeat') {
          <path d="M17 2l3 3-3 3M7 22l-3-3 3-3" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
          <path d="M4 12a8 8 0 0 1 12.93-6.29M20 12a8 8 0 0 1-12.93 6.29" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('branch') {
          <path d="M6 3v12M18 3v6M6 15a6 6 0 0 0 6-6h6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
          <circle cx="6" cy="18" r="2" stroke="currentColor" stroke-width="2" fill="none"/>
        }
        @case ('rectangles-group') {
          <rect x="3" y="3" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="2" fill="none"/>
          <rect x="13" y="3" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="2" fill="none"/>
          <rect x="3" y="13" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="2" fill="none"/>
          <rect x="13" y="13" width="8" height="8" rx="1.5" stroke="currentColor" stroke-width="2" fill="none"/>
        }
        @case ('house') {
          <path d="M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10.5z" stroke="currentColor" stroke-width="2" stroke-linejoin="round" fill="none"/>
          <path d="M9 21V13h6v8" stroke="currentColor" stroke-width="2" stroke-linejoin="round" fill="none"/>
        }
        @case ('slider-horizontal') {
          <path d="M4 12h16M8 8v8M16 8v8" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('arrow-right') {
          <path d="M5 12h14M13 6l6 6-6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
        }
        @case ('magnifying-glass') {
          <circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M15.5 15.5L20 20" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('sun') {
          <circle cx="12" cy="12" r="4" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('moon') {
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" stroke="currentColor" stroke-width="2" stroke-linejoin="round" fill="none"/>
        }
        @case ('wifi') {
          <path d="M12 19h.01M8.53 15.47a4.5 4.5 0 0 1 6.94 0M5.06 11.94a8.5 8.5 0 0 1 13.88 0M1.59 8.41a12.5 12.5 0 0 1 20.82 0" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('wifi-off') {
          <path d="M12 19h.01M8.53 15.47a4.5 4.5 0 0 1 6.94 0M3 3l18 18" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('gear') {
          <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" stroke="currentColor" stroke-width="2" fill="none"/>
        }
        @case ('stop-circle') {
          <circle cx="12" cy="12" r="10" fill="currentColor"/>
          <rect x="9" y="9" width="6" height="6" rx="0.5" fill="white"/>
        }
        @case ('exclamation-triangle') {
          <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M12 9v4M12 17h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('copy') {
          <rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" stroke-width="2" fill="none"/>
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" stroke="currentColor" stroke-width="2" fill="none"/>
        }
        @case ('spinner') {
          <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none" opacity="0.25"/>
          <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('menu') {
          <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @case ('xmark') {
          <path d="M6 6l12 12M18 6L6 18" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
        }
        @default {
          <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none"/>
        }
      }
    </svg>
  `,
  styles: [`
    :host {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    svg {
      display: block;
    }
  `]
})
export class IconComponent {
  name = input.required<string>();
  size = input(24);
}
