name: OpenWrt Builder

on:
  workflow_dispatch:
    inputs:
      clean_build:
        description: 'Perform clean build'
        required: false
        default: 'false'

env:
  REPO_URL: https://github.com/coolsnowwolf/lede
  REPO_BRANCH: master
  TZ: Asia/Shanghai
  CLEAN_BUILD: ${{ inputs.clean_build }}

jobs:
  build:
    runs-on: ubuntu-22.04
    timeout-minutes: 180

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Environment
      run: |
        sudo apt-get update
        sudo apt-get install -y \
          build-essential ccache cmake git g++-multilib \
          libssl-dev python3 rsync unzip wget

    - name: Clone Source
      run: |
        [ "$CLEAN_BUILD" = "true" ] && rm -rf openwrt || true
        git clone --depth=1 $REPO_URL -b $REPO_BRANCH openwrt
        cd openwrt
        git submodule update --init --recursive

    - name: Configure Kwrt DIY
      run: |
        cd openwrt
        mkdir -p diy

        # 稀疏克隆 Kwrt 配置
        if [ ! -d "diy/devices" ]; then
          echo "::group::🚀 下载 Kwrt 配置"
          git clone --filter=blob:none --no-checkout \
            https://github.com/kiddin9/Kwrt.git diy-temp
          git -C diy-temp checkout 389060a43dc9812af124e225fb4dc17363944fa8 \
            -- devices/common/diy
          mv diy-temp/devices diy/
          rm -rf diy-temp
          echo "::endgroup::"
        fi

        # 配置 feeds
        echo "::group::📦 配置软件源"
        {
          echo "src-git packages https://github.com/coolsnowwolf/packages"
          echo "src-git luci https://github.com/coolsnowwolf/luci"
          [ -d "diy/devices/common/diy/package/feeds" ] && \
            find diy/devices/common/diy/package/feeds -name '*.feed' | xargs cat
        } > feeds.conf.default
        cat feeds.conf.default
        echo "::endgroup::"

    - name: Update Feeds
      run: |
        cd openwrt
        echo "::group::🔄 更新软件源"
        ./scripts/feeds update -a
        ./scripts/feeds install -a
        echo "::endgroup::"

    - name: Apply Configuration
      run: |
        cd openwrt
        echo "::group::⚙️ 应用配置"
        if [ -f "diy/devices/common/diy/package/config" ]; then
          cp -v diy/devices/common/diy/package/config .config
        else
          make defconfig
        fi
        echo "::endgroup::"

    - name: Download Packages
      run: |
        cd openwrt
        echo "::group::⬇️ 下载依赖包"
        make download -j$(nproc)
        find dl -size -1k -delete -print
        echo "::endgroup::"

    - name: Build Firmware
      run: |
        cd openwrt
        echo "::group::🔨 开始编译"
        make -j$(($(nproc)+1)) || make -j1 V=s
        echo "::endgroup::"

    - name: Upload Artifacts
      uses: actions/upload-artifact@v4
      with:
        name: openwrt-firmware-${{ github.run_id }}
        path: openwrt/bin/targets/*/*
        retention-days: 3
