import { Directive, ElementRef, inject, input, OnInit, OnDestroy, Renderer2 } from '@angular/core';

@Directive({
  selector: '[appPullToRefresh]',
  standalone: true,
})
export class PullToRefreshDirective implements OnInit, OnDestroy {
  appPullToRefresh = input.required<() => void>();

  private el = inject(ElementRef);
  private renderer = inject(Renderer2);

  private indicator!: HTMLElement;
  private progressCircle!: SVGCircleElement;

  private touchStartY = 0;
  private pulling = false;
  private refreshing = false;
  private pullDistance = 0;

  private readonly THRESHOLD = 70;
  private readonly MAX_PULL = 90;
  private readonly DEAD_ZONE = 10;
  private readonly CIRCLE_CIRCUMFERENCE = 2 * Math.PI * 10; // radius=10

  private boundTouchStart = this.onTouchStart.bind(this);
  private boundTouchMove = this.onTouchMove.bind(this);
  private boundTouchEnd = this.onTouchEnd.bind(this);

  ngOnInit(): void {
    this.createIndicator();
    const host = this.el.nativeElement as HTMLElement;
    host.style.position = 'relative';
    host.style.overscrollBehavior = 'contain';

    host.addEventListener('touchstart', this.boundTouchStart, { passive: true });
    host.addEventListener('touchmove', this.boundTouchMove, { passive: false });
    host.addEventListener('touchend', this.boundTouchEnd, { passive: true });
  }

  ngOnDestroy(): void {
    const host = this.el.nativeElement as HTMLElement;
    host.removeEventListener('touchstart', this.boundTouchStart);
    host.removeEventListener('touchmove', this.boundTouchMove);
    host.removeEventListener('touchend', this.boundTouchEnd);
  }

  private createIndicator(): void {
    // Add keyframes if not already present
    if (!document.getElementById('ptr-keyframes-v2')) {
      const style = document.createElement('style');
      style.id = 'ptr-keyframes-v2';
      style.textContent = `@keyframes ptr-spin-v2 { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }`;
      document.head.appendChild(style);
    }

    this.indicator = this.renderer.createElement('div');
    Object.assign(this.indicator.style, {
      position: 'absolute',
      top: '0',
      left: '0',
      right: '0',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      height: '0',
      overflow: 'hidden',
      transition: 'height 350ms cubic-bezier(0.34, 1.56, 0.64, 1)',
      zIndex: '50',
      pointerEvents: 'none',
    });

    // Create SVG circle progress indicator
    const svgContainer = document.createElement('div');
    Object.assign(svgContainer.style, {
      width: '32px',
      height: '32px',
      borderRadius: '50%',
      background: 'var(--bg-card)',
      boxShadow: '0 2px 8px rgba(0,0,0,0.12)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
    });

    const svgNS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(svgNS, 'svg');
    svg.setAttribute('width', '24');
    svg.setAttribute('height', '24');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.style.transition = 'transform 0.15s ease';

    // Background circle
    const bgCircle = document.createElementNS(svgNS, 'circle');
    bgCircle.setAttribute('cx', '12');
    bgCircle.setAttribute('cy', '12');
    bgCircle.setAttribute('r', '10');
    bgCircle.setAttribute('fill', 'none');
    bgCircle.setAttribute('stroke', 'var(--border-color)');
    bgCircle.setAttribute('stroke-width', '2.5');
    svg.appendChild(bgCircle);

    // Progress circle
    this.progressCircle = document.createElementNS(svgNS, 'circle') as SVGCircleElement;
    this.progressCircle.setAttribute('cx', '12');
    this.progressCircle.setAttribute('cy', '12');
    this.progressCircle.setAttribute('r', '10');
    this.progressCircle.setAttribute('fill', 'none');
    this.progressCircle.setAttribute('stroke', 'var(--tint-main)');
    this.progressCircle.setAttribute('stroke-width', '2.5');
    this.progressCircle.setAttribute('stroke-linecap', 'round');
    this.progressCircle.setAttribute('stroke-dasharray', `${this.CIRCLE_CIRCUMFERENCE}`);
    this.progressCircle.setAttribute('stroke-dashoffset', `${this.CIRCLE_CIRCUMFERENCE}`);
    this.progressCircle.style.transition = 'stroke-dashoffset 0.1s ease';
    this.progressCircle.style.transform = 'rotate(-90deg)';
    this.progressCircle.style.transformOrigin = 'center';
    svg.appendChild(this.progressCircle);

    svgContainer.appendChild(svg);
    this.indicator.appendChild(svgContainer);

    // Store refs for animation
    (this.indicator as any)._svg = svg;
    (this.indicator as any)._container = svgContainer;

    const host = this.el.nativeElement as HTMLElement;
    this.renderer.insertBefore(host, this.indicator, host.firstChild);
  }

  private onTouchStart(e: TouchEvent): void {
    if (this.refreshing) return;
    const host = this.el.nativeElement as HTMLElement;
    if (host.scrollTop <= 0) {
      this.touchStartY = e.touches[0].clientY;
      this.pulling = false;
      this.pullDistance = 0;
    }
  }

  private onTouchMove(e: TouchEvent): void {
    if (this.refreshing) return;
    if (this.touchStartY === 0) return;

    const host = this.el.nativeElement as HTMLElement;
    if (host.scrollTop > 0) {
      this.touchStartY = 0;
      this.pulling = false;
      return;
    }

    const dy = e.touches[0].clientY - this.touchStartY;

    if (dy < this.DEAD_ZONE) {
      if (this.pulling) {
        this.resetIndicator();
        this.pulling = false;
      }
      return;
    }

    e.preventDefault();
    this.pulling = true;

    // Rubber-band effect: diminishing returns past threshold
    const raw = dy - this.DEAD_ZONE;
    this.pullDistance = Math.min(raw * 0.5, this.MAX_PULL);

    this.indicator.style.transition = 'none';
    this.indicator.style.height = `${this.pullDistance}px`;

    // Update circle progress
    const progress = Math.min(this.pullDistance / this.THRESHOLD, 1);
    const offset = this.CIRCLE_CIRCUMFERENCE * (1 - progress);
    this.progressCircle.setAttribute('stroke-dashoffset', `${offset}`);
    this.progressCircle.style.transition = 'none';
  }

  private onTouchEnd(): void {
    if (this.refreshing) return;

    if (this.pulling && this.pullDistance >= this.THRESHOLD) {
      this.triggerRefresh();
    } else {
      this.resetIndicator();
    }

    this.touchStartY = 0;
    this.pulling = false;
  }

  private triggerRefresh(): void {
    this.refreshing = true;

    // Show at fixed height with spinning animation
    this.indicator.style.transition = 'height 350ms cubic-bezier(0.34, 1.56, 0.64, 1)';
    this.indicator.style.height = '48px';

    // Full circle + spin
    this.progressCircle.setAttribute('stroke-dashoffset', '0');
    const svg = (this.indicator as any)._svg as SVGElement;
    if (svg) {
      svg.style.animation = 'ptr-spin-v2 0.8s linear infinite';
    }

    // Call refresh callback
    const fn = this.appPullToRefresh();
    fn();

    // Auto-dismiss after a reasonable time
    setTimeout(() => {
      if (svg) {
        svg.style.animation = '';
      }
      this.resetIndicator();
      this.refreshing = false;
      // Reset circle to empty
      this.progressCircle.style.transition = '';
      this.progressCircle.setAttribute('stroke-dashoffset', `${this.CIRCLE_CIRCUMFERENCE}`);
    }, 1000);
  }

  private resetIndicator(): void {
    this.indicator.style.transition = 'height 350ms cubic-bezier(0.34, 1.56, 0.64, 1)';
    this.indicator.style.height = '0';
    this.pullDistance = 0;
  }
}
