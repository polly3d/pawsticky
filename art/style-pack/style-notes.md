# 风格包冻结记录

- **选定:B 扁平矢量(Flat Vector)+ 后期统一描边**
- 日期:2026-09-30(用户决策)
- 决策依据:155px widget 尺寸三风格对比(剪影辨识/便签叠字/缩放存活率三项全优);描边后处理补足 A 风格才有的任意壁纸鲁棒性
- 淘汰去向:C(手绘水彩)不用于小组件,**保留为大尺寸物料风格**(分享卡片/节日贺卡,v1.0 后评估);A(厚涂贴纸)存档备查,若未来做"宠物世界"大画布场景可复活
- 定稿参考图:`frozen/` 下 4 张(B_cat-sitting / B_cat-standing / B_corgi-sitting / B_corgi-standing)+ `_outlined-demo.png`(描边效果演示)

## 完整提示词(风格段,后续所有生成强制引用)

**主体段模板**:`A cute orange tabby cat / corgi dog, [姿势: sitting upright / standing on hind legs], full body, front paws holding up a blank sticky note sign facing the viewer, the note occupies the lower third of the frame and is completely blank, plain white background, no text, no letters, no watermark, no realistic photo style, chibi proportions with head-to-body ratio about 1:1, clean silhouette suitable for cutout`

**风格段(B)**:`flat vector illustration, minimal geometric shapes, simple two-tone shading, limited palette of exactly 5 colors with one dominant pastel, crisp edges, modern app-icon aesthetic, calm tidy mood`

**已知问题与对策**(视觉分析发现):
- 柯基白胸毛与淡黄便签明度接近 → 描边后处理兜底
- 坐姿下半身被便签遮挡、姿态区分弱 → 姿势库生成时强化尾巴/耳朵差异词
- 生成参数:model `openai/gpt-image-2.5-flare`(OpenRouter),quality high,1:1,1024×1024;单张成本 ~$0.053

## 描边后处理规格(生产资产统一执行)

```bash
magick <input> \( +clone -alpha extract -morphology dilate disk:3 \
  -background "#5B4636" -alpha shape \) -compose DstOver -composite <output>
```
- 描边宽:disk:3(≈3px @1024;@3x 资产按比例)
- 描边色:`#5B4636`(深棕,取自暖色系主调;上 widget 前在深/浅背景下各验一次)
- 演示产物:`frozen/_outlined-demo.png`

## 角色卡

- `art/characters/cat/cat-character-sheet.webp`、`art/characters/corgi/corgi-character-sheet.webp`(各含正/侧/背三视图,16:9)
- ⚠️ 限制:当前脚本为纯文生图(无图参考输入)。后续姿势/装扮生成需以角色卡作参考图——在 gpt-image-2.5 对话端手动挂参考图,或给 gen-images.sh 扩展 `image` 字段(OpenRouter images API 支持时)。**在支持参考图之前,禁止批量生成新姿势**(防风格漂移,见商业计划 §4.5 三件套)

## 管线说明

- 脚本:`art/scripts/gen-images.sh`(适配自 ~/Project/ai/tryon/scripts/gen-images.sh,感谢 WigTryOn 项目)
- prompts:`art/scripts/prompts/{candidates,characters}.json`(id/prompt/aspect_ratio/resize/output_dir/filename)
- key:`OPENROUTER_API_KEY`,读取顺序 环境变量 → `art/scripts/.env.gen` → 回退 tryon 的 `.env.gen`
- 原始 PNG 母版:`art/scripts/.tmp/raw/`(不入库,webp 为工作格式;进入 App 资产时从母版导出 @1x/2x/3x PNG)
