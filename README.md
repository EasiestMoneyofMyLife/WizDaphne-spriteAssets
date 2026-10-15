# WizDaphne Sprite Assets

《Wizardry Variants Daphne》的游戏内图片资源仓库，按游戏版本整理。

使用[AssetStudioMod](https://github.com/aelurum/AssetStudioMod)解包的外部未加密资源。

需要更详细的加密资源，请参考[wizdaphne-unpack](https://github.com/yueecui/wizdaphne-unpack)


## 下载

进入[releases](https://github.com/EasiestMoneyofMyLife/WizDaphne-spriteAssets/releases)页面，下载对应版本的资源。
* Verx.xx.x_full.zip：该版本的完整资源。
* Verx.xx.x_new.zip：该版本相比上一版的新增资源。


## 维护

### 1. 克隆仓库
```
git clone https://github.com/EasiestMoneyofMyLife/WizDaphne-spriteAssets.git
```

### 2. 解包新内容
使用AssetStudioMod解包新内容，并将Sprite资源放入仓库根目录（WizDaphne-spriteAssets/）

### 3. 重建上版本的完整内容
```
bash rebuild_full.sh Ver1.37.0
# 输出 Ver1.37.0_full/，包含 Old/ 到 Ver1.37.0/ 的全部内容
```

### 4. 筛查新版本资源
```
bash classify_and_diff.sh Sprite Ver1.37.5
# 输出 Ver1.37.5/
```

### 5. 提交、推 tag
```
git add Ver1.37.5/
git commit -m "Ver1.37.5"
git push origin main
git tag -a Ver1.37.5 -m "Ver1.37.5"
git push origin Ver1.37.5
# 工作流自动根据tag打包release
```
