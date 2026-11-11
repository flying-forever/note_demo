import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

export class NoteShare {
  private controller?: systemShare.ShareController;
  private active: boolean = false;
  private dismiss = (): void => {
    this.active = false;
    this.controller?.off('dismiss', this.dismiss);
    this.controller = undefined;
  };

  async show(context: common.UIAbilityContext, title: string, content: string): Promise<string> {
    if (this.active) { return ''; }
    const parts: string[] = [];
    if (title.trim()) { parts.push(title); }
    if (content.trim()) { parts.push(content); }
    if (parts.length === 0) { return '请填写标题或正文后再分享'; }
    this.active = true;
    try {
      const data = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT, content: parts.join('\n\n')
      });
      this.controller = new systemShare.ShareController(data);
      this.controller.on('dismiss', this.dismiss);
      await this.controller.show(context, {});
      return '';
    } catch {
      this.dismiss();
      return '暂时无法打开分享，请稍后重试';
    }
  }

  dispose(): void { this.dismiss(); }
}
