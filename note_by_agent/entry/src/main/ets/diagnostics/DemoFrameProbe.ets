// 将界面空闲帧回调转交给技术实验的测量逻辑。
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
