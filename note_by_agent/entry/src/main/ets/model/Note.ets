export interface Note {
  id: string;
  title: string;
  content: string;
  timeLabel: string;
  group: string;
}

export function noteCardTitle(note: Note): string {
  const title: string = note.title.trim();
  return title.length > 0 ? title : note.content.trim().split('\n')[0].trim();
}

export const GROUP_ALL: string = '全部';

export const GROUP_UNFILED: string = '未分类';
export const NOTE_GROUPS: string[] = ['全部', '旅途', '美食', '攻略', '随记', GROUP_UNFILED];

export const FAKE_NOTES: Note[] = [
  {
    id: 'n01',
    title: '京都的清晨',
    content: '五点半起床，鸭川边已经有人在跑步。风有点凉，买了罐热咖啡，坐在河堤上看天色一点点亮起来。',
    timeLabel: '今天 07:42',
    group: '旅途'
  },
  {
    id: 'n02',
    title: '夜行巴士到京都',
    content: '第一次坐夜行巴士，座位比想象中窄，但省下一晚住宿钱。到站时天刚亮。',
    timeLabel: '昨天 23:10',
    group: '旅途'
  },
  {
    id: 'n03',
    title: '鸭川边的咖啡馆',
    content: '点了一杯手冲和一块芝士蛋糕，坐在靠窗的位置，看了一下午的书。',
    timeLabel: '昨天 15:26',
    group: '美食'
  },
  {
    id: 'n04',
    title: '第一次在日本坐地铁',
    content: '进站前先看清楚线路颜色，换乘时跟着地面标识走。交通卡在自动售票机上就能买，记得准备现金。',
    timeLabel: '昨天 09:03',
    group: '攻略'
  },
  {
    id: 'n05',
    title: '清水寺的日落',
    content: '从二年坂一路走上去，人很多。站在舞台上往下看，整片屋顶被夕阳染成橙色，值回票价。',
    timeLabel: '10月28日 18:40',
    group: '旅途'
  },
  {
    id: 'n06',
    title: '锦市场小吃清单',
    content: '玉子烧、章鱼小丸子、抹茶冰淇淋、烤扇贝。建议早点去，中午人挤人。',
    timeLabel: '10月28日 12:15',
    group: '美食'
  },
  {
    id: 'n07',
    title: '行李打包清单',
    content: '护照、现金、交通卡、充电宝、转换插头、薄外套、雨伞、常用药。',
    timeLabel: '10月27日 21:05',
    group: '攻略'
  },
  {
    id: 'n08',
    title: '在奈良被小鹿追着跑',
    content: '买了鹿仙贝，结果被三只鹿围住。饼干举高一点它们就会鞠躬，很可爱也很好笑。',
    timeLabel: '10月27日 16:30',
    group: '随记'
  },
  {
    id: 'n09',
    title: '大阪的章鱼烧',
    content: '外皮很脆，里面是流心的，烫到舌头也停不下来。老板还送了我们一小份炒面。',
    timeLabel: '10月26日 20:12',
    group: '美食'
  },
  {
    id: 'n10',
    title: '去岚山的那趟小火车',
    content: '靠窗的位置要提前订。沿着保津川开，秋天两岸都是红叶。',
    timeLabel: '10月26日 10:08',
    group: '旅途'
  },
  {
    id: 'n11',
    title: '民宿老板推荐的路线',
    content: '早上先去伏见稻荷，午后人少再去清水寺。晚上回四条吃串烧。',
    timeLabel: '10月25日 19:45',
    group: '攻略'
  },
  {
    id: 'n12',
    title: '雨天躲在书店一下午',
    content: '雨一直没停，就在书店的咖啡区待着。翻完一本摄影集，买了一张明信片。',
    timeLabel: '10月25日 14:20',
    group: '随记'
  },
  {
    id: 'n13',
    title: '伏见稻荷的千本鸟居',
    content: '建议七点前到，几乎没人。往上走四十分钟可以到观景台，俯瞰整座京都。',
    timeLabel: '10月24日 09:30',
    group: '旅途'
  },
  {
    id: 'n14',
    title: '一兰拉面排队四十分钟',
    content: '晚上十点还在排队。汤头很浓，辣度选了二倍，下次想试试三倍。',
    timeLabel: '10月23日 19:50',
    group: '美食'
  },
  {
    id: 'n15',
    title: '交通卡怎么买最划算',
    content: '短途刷单次票，长途用一日券。关西周游券适合连着跑大阪、京都、奈良。',
    timeLabel: '10月23日 08:15',
    group: '攻略'
  },
  {
    id: 'n16',
    title: '在便利店解决的一顿晚饭',
    content: '饭团、关东煮和一瓶热茶，坐在民宿的小桌子前吃完，居然很满足。',
    timeLabel: '10月22日 22:05',
    group: '随记'
  },
  {
    id: 'n17',
    title: '大阪城公园的银杏',
    content: '树叶黄了一半，风一吹就下金色的雨。公园里有很多遛狗的人。',
    timeLabel: '10月22日 15:40',
    group: '旅途'
  },
  {
    id: 'n18',
    title: '心斋桥买到的旧唱片',
    content: '在一家二手唱片店翻了半小时，找到一张二十年前的爵士专辑。',
    timeLabel: '10月21日 17:25',
    group: '随记'
  },
  {
    id: 'n19',
    title: '神户牛肉初体验',
    content: '铁板上滋滋作响，第一口几乎入口即化。贵是真的贵，但值得一次。',
    timeLabel: '10月20日 19:00',
    group: '美食'
  },
  {
    id: 'n20',
    title: '回程前的最后一个早晨',
    content: '把民宿的窗户打开，又听了会儿街上的声音。行李比来时多了一袋伴手礼。',
    timeLabel: '10月20日 06:50',
    group: '旅途'
  },
  {
    id: 'n21',
    title: '临时记下的想法',
    content: '周末整理照片，挑几张喜欢的打印出来。还没想好放进哪个文件夹，先记在这里。',
    timeLabel: '10月19日 20:15',
    group: ''
  },
  {
    id: 'n22',
    title: '',
    content: '下班路上记得取快递，顺便买一盒牛奶。',
    timeLabel: '10月19日 18:30',
    group: ''
  }
];
