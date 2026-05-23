# 3D 踩坑记录

本项目（血肉之战）开发过程中遇到的 3D 相关问题和解决方案。

---

## 1. 手牌定位：屏幕底部固定卡牌的正确做法

### 问题

手牌需要固定在屏幕底部（类似炉石），不随相机俯瞰角度变化。

尝试过的**错误方案**：

| 方案 | 结果 |
|------|------|
| `camera:GetScreenRay` 投射到桌面平面 | 卡牌落在桌面上而不是"悬浮在屏幕底部" |
| 固定世界坐标 `(0, 0.3, -5.8)` | 相机在 Z=-4.5，卡牌在 Z=-5.8 直接跑到相机背后，不可见 |
| 固定世界坐标 `(0, 0.3, -3.0)` | 可见但卡牌太小，且随相机呼吸晃动会偏移 |

### 解决方案：相机容器节点

将手牌挂载为相机节点的**子节点**，使用相机局部坐标：

```lua
-- 创建容器作为相机子节点
local container = cameraNode:CreateChild("HandContainer")
container.position = Vector3(0, -0.9, 3.0)  -- 相机局部：下方 0.9m，前方 3.0m

-- 卡牌加入容器
container:AddChild(card.node)
card.node.position = Vector3(x, 0, 0)  -- 容器局部坐标
```

**关键参数推导**（FOV=50°）：
- 半角 = 25°，tan(25°) = 0.466
- Z=3.0 时视口半高 = 3.0 × 0.466 = 1.40m
- 容器 Y=-0.9 → 距视口底部 0.50m → 卡牌出现在屏幕下方约 1/3 处
- 16:9 屏幕半宽 = 1.40 × 16/9 ≈ 2.49m → 足够展开 6 张卡

### 教训

> 需要"固定在屏幕某个位置"的 3D 物体，不要用世界坐标硬编码，挂到相机子节点用局部坐标。

---

## 2. 节点重新挂载（re-parenting）必须保存世界变换

### 问题

拖拽卡牌时需要从相机容器脱离到场景根（世界坐标跟随鼠标），松手后回挂到容器。`AddChild` 只保留 local transform，挂载后卡牌会"跳"到错误位置。

### 解决方案

脱离和回挂时手动保存/恢复世界变换：

```lua
-- 脱离容器
local wPos = card.node.worldPosition
local wRot = card.node.worldRotation
scene:AddChild(card.node)
card.node.worldPosition = wPos  -- 恢复世界位置
card.node.worldRotation = wRot

-- 回挂容器（同理）
local wPos = card.node.worldPosition
local wRot = card.node.worldRotation
container:AddChild(card.node)
card.node.worldPosition = wPos
card.node.worldRotation = wRot
```

### 教训

> `AddChild` 后节点的 `position` 变成相对于新父节点的局部坐标，世界位置会突变。必须先存 `worldPosition/worldRotation`，挂载后写回。

---

## 3. 扇面角度方向：yaw 符号与视觉直觉相反

### 问题

手牌扇形展开后"上面收敛、下面扩散"，和现实中手持卡扇的方向反了（应该底部收敛、顶部扩散）。

### 原因

卡牌前倾 -75° 后，yaw 旋转的视觉方向会反转：

```lua
-- 错误：左侧卡 (t<0) 得到正 yaw → 顶部向内
local yawAngle = -t * arcDeg * 0.5

-- 正确：左侧卡 (t<0) 得到负 yaw → 底部向内（手持扇面）
local yawAngle = t * arcDeg * 0.5
```

### 教训

> 对倾斜物体施加旋转时，视觉方向可能和直觉相反。先用 1-2 张卡测试方向，再调整符号。

---

## 4. 出牌后卡牌插进桌面：动画必须处理旋转

### 问题

卡牌从手牌拖到战斗链后，一半卡在桌面下面。

### 原因

`playThrow` 动画只做了**位置弧线和缩放**，没有修改旋转。卡牌从相机容器脱离后仍保留 -75° 前倾旋转，到达桌面 Y=0.03 时斜插进去：

```
容器中的卡牌姿态：前倾 -75°
     ╲
      ╲  ← 到了桌面还是这个角度
───────╲──── 桌面 Y=0
        ╲  ← 一半在桌面下
```

### 解决方案

`playThrow` 中用 `Slerp` 将旋转从拖拽姿态过渡到平放：

```lua
local startRot = card.node.worldRotation
local targetRot = Quaternion(0, 0, 0)  -- 平放

-- 动画中
card.node.worldRotation = startRot:Slerp(targetRot, easedT)
```

同时注意：
- 卡牌已脱离容器在场景根，用 `worldPosition` / `worldRotation` 操作
- 缩放也要从拖拽放大（1.2x）恢复到原始大小

### 教训

> 跨坐标空间的动画（从容器到世界），position、rotation、scale 三者都要处理。漏掉旋转是最常见的遗忘。

---

## 5. position vs worldPosition：坐标空间必须一致

### 问题

拖拽平面 Y 值用了 `card.node.position.y`（容器局部坐标），但鼠标射线交点是世界坐标，导致拖拽跟随平面偏移。

### 规则

| 卡牌在哪 | 用什么 | 含义 |
|---------|--------|------|
| 相机容器中 | `node.position` | 相对容器的局部坐标 |
| 相机容器中 | `node.worldPosition` | 世界坐标（含相机位移和旋转） |
| 场景根下 | `node.position` | 就是世界坐标（父节点无变换） |

```lua
-- 拖拽平面 Y 需要世界坐标（和鼠标射线匹配）
self.dragPlaneY = card.node.worldPosition.y  -- 正确
self.dragPlaneY = card.node.position.y       -- 错误（容器局部 Y ≈ 0）
```

### 教训

> 涉及鼠标交互（射线、屏幕投影）的计算一律用 `worldPosition`。只有布局排列等"同一父节点下的相对关系"才用 `position`。

---

## 6. 战斗链卡牌重叠：间距公式的代数陷阱

### 问题

战斗链出了 3 张牌全叠在一起。

### 原因

原公式看起来"没问题"：
```lua
local spacing = Card3D.WIDTH + 0.05  -- 0.68m
local x = def.pos.x + (n - 0.5) * spacing - (n * spacing) / 2
```

展开化简：
```
x = pos.x + n*sp - 0.5*sp - n*sp/2
  = pos.x + n*sp/2 - 0.5*sp
```

n=0 → x = -0.34, n=1 → x = 0, n=2 → x = 0.34

卡间距 0.34m < 卡宽 0.63m → 重叠。

### 修复

```lua
local spacing = Card3D.WIDTH + 0.10  -- 0.73m > 卡宽 0.63m
local x = def.pos.x + n * spacing    -- 简单递增
```

### 教训

> 排列公式写完后做一次手算代入验证（n=0,1,2），检查实际间距是否大于物体宽度。
