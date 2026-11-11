import { FrameCallback } from '@kit.ArkUI';

export class DemoFrameProbe extends FrameCallback {
  private callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onIdle(timeLeftInNano: number): void {
    this.callback();
  }
}
