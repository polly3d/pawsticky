# PawIt 美术任务包(Task 5 · gpt-image-2.5 · 风格冻结)

> 对应《开发计划-PawIt-MVP.md》§5 Task 5。目标:**3 套候选风格 → 选 1 → 冻结风格包 → 猫/狗角色卡**。
> 本文件由控制器(Claude)生成;生成图片与风格决策由你执行(审美决策权在你)。

---

## 一、流程(约 30-45 分钟)

1. 用下面三组提示词各生成 **4 张**(猫×2 姿势 + 狗×2 姿势),共 12 张
2. 三套横向对比,按"四、选择标准"挑 1 套
3. 用选定风格生成**角色卡**(模板在"五")
4. 产物按"六、目录结构"归档,告诉控制器入库 → Task 5 勾选,进 Task 6 收口

## 二、通用生成规格(所有提示词共用,拼在每条 prompt 后)

```
Full body, upright seated or standing pose, front paws holding up a blank
sticky-note sign facing the viewer, note occupies the lower third of the
frame and is completely blank, plain white background, no text, no letters,
no watermark, no realistic photo style, chibi proportions (head-to-body
about 1:1), clean silhouette suitable for cutout, square 1024x1024
```

**要点**:便签空白 + 占下方 1/3(后期程序叠字);纯白背景利抠图;Q 版头身比;禁止照片写实。

## 三、三套候选风格提示词(猫版;狗版把主体词替换,风格段不变)

### 风格 A · 厚涂贴纸风(Sticker Thick-Paint)
```
A cute orange tabby cat, [通用规格段] +
thick-paint digital sticker illustration, bold rounded outlines, soft
sculpted shading, warm saturated palette (amber / cream / coral), die-cut
sticker look with thin white border, playful and friendly mood
```

### 风格 B · 扁平矢量风(Flat Vector)
```
A cute orange tabby cat, [通用规格段] +
flat vector illustration, minimal geometric shapes, 2-tone shading,
limited palette of exactly 5 colors with one dominant pastel, crisp edges,
modern app-icon aesthetic, calm and tidy mood
```

### 风格 C · 手绘水彩风(Hand-drawn Watercolor)
```
A cute orange tabby cat, [通用规格段] +
hand-drawn watercolor illustration, soft wet edges, gentle paper texture,
loose expressive linework, warm muted palette (peach / sage / sand),
cozy storybook mood
```

狗版主体词:`A cute corgi dog`(柯基)/ `A cute shiba inu dog`(柴犬,选你喜欢的)。

## 四、选择标准(按优先级)

1. **小尺寸辨识度**(最重要):把候选图缩到 ~155×155px(widget 实际渲染尺寸)再对比——剪影是否还能一眼认出是"举牌的猫/狗"?
2. **便签区可用性**:空白便签区域够大、够平整,程序叠两行字后不违和吗?
3. **系列一致性潜力**:同风格 4 张放一起,像同一个产品吗?(这是"角色卡 + 参考图"能锁住风格的前提)
4. **情绪匹配**:产品口号是"由你的宠物帮你记住事情"——哪套更"想让你每天看"?
5. 竞品参考:领导者 Sticky Widgets 是纯扁平工具风——**风格 A(贴纸)与它的区分度最高**,B 最安全但同质化风险,C 最温柔但小尺寸细节易糊。仅供倾向参考,决定权在你。

## 五、角色卡模板(选定风格后,每只宠物一份)

```
Character reference sheet of the same cute orange tabby cat from the
attached reference image, three views: front, side, back, [选定风格的风格段],
consistent proportions and colors across all three views, plain white
background, no text, no watermark
```

> 之后所有姿势/装扮/表情生成都以角色卡为参考图喂入(gpt-image-2.5 的 character reference),**禁止裸提示词重抽**——这是 §4.5 防风格漂移三件套的第一件。

## 六、目录结构(归档格式)

```
art/
├── README.md                 # 本文件
├── style-pack/
│   ├── candidates/           # 三套候选 × 4 张
│   │   ├── A-sticker/
│   │   ├── B-flat-vector/
│   │   └── C-watercolor/
│   ├── frozen/               # 选定风格的 4-6 张定稿参考图(冻结)
│   └── style-notes.md        # 冻结记录:选了哪套 / 完整提示词 / 参数 / 日期
└── characters/               # 角色卡(正/侧/背 × 每只宠物)
    ├── cat/
    └── dog/
```

`style-notes.md` 模板:

```markdown
# 风格包冻结记录
- 选定:B-flat-vector(示例)
- 日期:2026-XX-XX
- 完整提示词(风格段):...
- 生成参数:...
- 参考图:frozen/ 下 6 张
- 备注:...(如:狗选了柯基;主色 #XXXXXX)
```

## 七、验收 checklist(每张定稿图入库前过一遍)

- [ ] 同批 4+ 张并排,线条/上色/描边风格一致
- [ ] 头身比稳定(Q 版约 1:1)
- [ ] 举牌透视正确:便签面朝观众、微倾 ≤10°、无诡异透视
- [ ] 便签空白且 ≥ 画面 1/4
- [ ] 配色 4-6 色且含明确主色
- [ ] 无文字 / 水印 / 复杂阴影 / 照片写实倾向
- [ ] 缩到 155×155px 剪影仍可辨识

---

*Task 5 完成标志:`style-pack/frozen/` + `style-notes.md` + 猫/狗角色卡齐备并入库。之后控制器执行 Task 6(《W1 架构备忘录》+ 打 tag `week-1`),W1 收官。*
