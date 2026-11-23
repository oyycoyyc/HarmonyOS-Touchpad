export interface InertiaStepResult {
  dx: number;
  dy: number;
  active: boolean;
}

interface VelocitySample {
  dx: number;
  dy: number;
  dtMs: number;
  timestampMs: number;
}

const SAMPLE_WINDOW_MS: number = 75;
const MAX_RELEASE_STALE_MS: number = 45;
const MIN_LAUNCH_SPEED_PER_MS: number = 0.30;
const MAX_LAUNCH_SPEED_PER_MS: number = 4.0;
const STOP_SPEED_PER_MS: number = 0.08;
const MAX_GLIDE_DURATION_MS: number = 1200;
const MAX_INERTIA_DELTA_PER_STEP: number = 48;
const DEFAULT_STRENGTH_PERCENT: number = 35;
const MAX_SAMPLE_COUNT: number = 12;

/**
 * Pure trackball-style pointer inertia kinematics simulator (zero ArkUI / Bluetooth / timer imports).
 * Combines viscous exponential damping with Coulomb dry bearing friction so flicks carry weighty
 * trackball momentum yet settle to a crisp, decisive stop instead of endlessly crawling.
 */
export class PointerInertiaSimulator {
  private enabled: boolean = false;
  private strengthPercent: number = DEFAULT_STRENGTH_PERCENT;
  private samples: Array<VelocitySample> = [];
  private lastSampleTimestampMs: number = 0;

  private vx: number = 0;
  private vy: number = 0;
  private remX: number = 0;
  private remY: number = 0;
  private gliding: boolean = false;
  private elapsedGlideMs: number = 0;

  public isEnabled(): boolean {
    return this.enabled;
  }

  public getStrengthPercent(): number {
    return this.strengthPercent;
  }

  public isGliding(): boolean {
    return this.gliding;
  }

  public setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled) {
      this.stop();
    }
  }

  public setStrengthPercent(percent: number): void {
    const rounded = Math.round(percent);
    if (rounded < 5) {
      this.strengthPercent = 5;
    } else if (rounded > 100) {
      this.strengthPercent = 100;
    } else {
      this.strengthPercent = rounded;
    }
  }

  public clearSamples(): void {
    this.samples = [];
    this.lastSampleTimestampMs = 0;
  }

  public stop(): void {
    this.gliding = false;
    this.vx = 0;
    this.vy = 0;
    this.remX = 0;
    this.remY = 0;
    this.elapsedGlideMs = 0;
    this.clearSamples();
  }

  public recordSample(dxCounts: number, dyCounts: number, timestampMs: number): void {
    if (!this.enabled) {
      return;
    }
    let dtMs = 12;
    if (this.lastSampleTimestampMs > 0) {
      dtMs = this.clampDt(timestampMs - this.lastSampleTimestampMs);
    }
    this.lastSampleTimestampMs = timestampMs;

    this.samples.push({
      dx: dxCounts,
      dy: dyCounts,
      dtMs: dtMs,
      timestampMs: timestampMs
    });

    this.pruneOldSamples(timestampMs);
    while (this.samples.length > MAX_SAMPLE_COUNT) {
      this.samples.shift();
    }
  }

  public startGlide(releaseTimestampMs: number): boolean {
    if (!this.enabled || this.samples.length === 0) {
      this.clearSamples();
      return false;
    }

    this.pruneOldSamples(releaseTimestampMs);
    if (this.samples.length === 0) {
      this.clearSamples();
      return false;
    }

    const newest = this.samples[this.samples.length - 1];
    if (releaseTimestampMs - newest.timestampMs > MAX_RELEASE_STALE_MS) {
      this.clearSamples();
      return false;
    }

    const n = this.samples.length;
    let sumDx = 0;
    let sumDy = 0;
    let sumDt = 0;
    for (let i = 0; i < n; i++) {
      const s = this.samples[i];
      const w = 0.5 + 0.5 * ((i + 1) / n);
      sumDx += w * s.dx;
      sumDy += w * s.dy;
      sumDt += s.dtMs;
    }

    this.clearSamples();
    if (sumDt <= 0) {
      return false;
    }

    const rawVx = sumDx / sumDt;
    const rawVy = sumDy / sumDt;
    const rawSpeed = Math.sqrt(rawVx * rawVx + rawVy * rawVy);
    if (rawSpeed < MIN_LAUNCH_SPEED_PER_MS) {
      return false;
    }

    const s = this.strengthPercent / 100;
    const boost = 0.90 + 0.70 * s;
    const launchSpeed = Math.min(rawSpeed * boost, MAX_LAUNCH_SPEED_PER_MS);
    const ratio = launchSpeed / rawSpeed;

    this.vx = rawVx * ratio;
    this.vy = rawVy * ratio;
    this.remX = 0;
    this.remY = 0;
    this.elapsedGlideMs = 0;
    this.gliding = true;
    return true;
  }

  public step(dtMs: number): InertiaStepResult {
    if (!this.gliding || !this.enabled) {
      this.stop();
      return { dx: 0, dy: 0, active: false };
    }

    const dt = this.clampDt(dtMs);
    const rawX = this.vx * dt + this.remX;
    const rawY = this.vy * dt + this.remY;
    const emitX = Math.trunc(rawX);
    const emitY = Math.trunc(rawY);
    this.remX = rawX - emitX;
    this.remY = rawY - emitY;

    const outX = this.clampDelta(emitX);
    const outY = this.clampDelta(emitY);

    const s = this.strengthPercent / 100;
    const tauMs = 60 + 200 * s;
    const dryDecel = 0.0055 - 0.0025 * s;
    const speed = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
    const nextSpeed = speed * Math.exp(-dt / tauMs) - dryDecel * dt;
    this.elapsedGlideMs += dt;

    if (nextSpeed < STOP_SPEED_PER_MS || this.elapsedGlideMs >= MAX_GLIDE_DURATION_MS || speed <= 0) {
      this.gliding = false;
      this.vx = 0;
      this.vy = 0;
      this.remX = 0;
      this.remY = 0;
      return { dx: outX, dy: outY, active: false };
    }

    const scale = nextSpeed / speed;
    this.vx *= scale;
    this.vy *= scale;
    return { dx: outX, dy: outY, active: true };
  }

  private pruneOldSamples(referenceTimestampMs: number): void {
    while (this.samples.length > 0 && referenceTimestampMs - this.samples[0].timestampMs > SAMPLE_WINDOW_MS) {
      this.samples.shift();
    }
  }

  private clampDt(dtMs: number): number {
    if (dtMs < 4) {
      return 4;
    }
    if (dtMs > 30) {
      return 30;
    }
    return dtMs;
  }

  private clampDelta(delta: number): number {
    if (delta > MAX_INERTIA_DELTA_PER_STEP) {
      return MAX_INERTIA_DELTA_PER_STEP;
    }
    if (delta < -MAX_INERTIA_DELTA_PER_STEP) {
      return -MAX_INERTIA_DELTA_PER_STEP;
    }
    return delta;
  }
}
