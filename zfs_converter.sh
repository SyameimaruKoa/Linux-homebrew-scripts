#!/bin/bash
#
# ZFSデータセット変換スクリプト
# 指定されたディレクトリをZFSデータセットに変換し、マウントポイントと圧縮設定を適用するスクリプトじゃ。
# UTF-8で保存すること
#

# --- ヘルプ表示関数 ---
show_help() {
  cat << EOF
使い方: ${0##*/} <対象ディレクトリ> <ZFSデータセット名> <圧縮設定>

このスクリプトは既存のディレクトリをZFSデータセットに変換するもんじゃ。

引数:
  対象ディレクトリ    変換したいディレクトリのフルパスを指定する。
                      これが新しいデータセットのマウントポイントになるぞ。

  ZFSデータセット名   作成する新しいZFSデータセットの名前じゃ。

  圧縮設定            新しいデータセットの圧縮設定じゃ。
                      'inherit' を指定すると、親データセットの設定を継承する。
                      利用可能なアルゴリズムの「全て」は以下の通りじゃ:

    --- 基本設定 ---
    on              : デフォルトのアルゴリズム (通常 lz4) を有効にする。
    off             : 圧縮を完全に無効にする。

    --- LZ系アルゴリズム ---
    lz4             : ★推奨★ 速度と圧縮率のバランスが良く、現在の標準じゃ。
    lzjb            : 古めの標準。速度は良いが lz4 に劣る。

    --- Gzip系アルゴリズム (高圧縮・高負荷) ---
    gzip            : gzip-6 の別名(エイリアス)じゃ。
    gzip-1          : 圧縮率は低いが、最も速いgzip。
    gzip-2          : ↓
    gzip-3          : │ 数字が上がるほど高圧縮になるが、負荷も増す。
    gzip-4          : │
    gzip-5          : │
    gzip-6          : (標準的なgzip設定)
    gzip-7          : │
    gzip-8          : │
    gzip-9          : 最も圧縮率が高いが、最も遅いgzip。

    --- Zstandard系アルゴリズム (高性能) ---
    zstd            : zstd-3 の別名。速度と圧縮のバランスが良い。
    zstd-1..19      : 標準レベル。数字が大きいほど高圧縮・高負荷じゃ。(例: zstd-1, zstd-10)
    zstd-fast-N     : 超高速レベル。圧縮率より速度を優先する。Nには1からの数字が入る。
                      (例: zstd-fast-1, zstd-fast-5)
    zstd-20..22     : ★注意★ 超高圧縮レベル。莫大なメモリを消費する！
                      システムに多大な負荷をかけるため、覚悟して使うのじゃな。

    --- その他 ---
    zle             : ゼロの連続だけを圧縮する。非常に軽量で、特定のデータに有効。

実行例:
  sudo ${0##*/} /var/www/html tank/webdata off
  sudo ${0##*/} /logs tank/logs gzip-9
  sudo ${0##*/} /vms tank/vms zstd-1
EOF
}

# --- ここから下のスクリプト本体は変更なし ---

# 引数のチェック
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi
if [ "$#" -ne 3 ]; then
  echo "エラー: 引数が足りんのじゃ。3つ必要じゃ。" >&2; echo ""; show_help; exit 1
fi

# 変数定義
TARGET_DIR="$1"; ZFS_DATASET="$2"; COMPRESSION_SETTING="$3"; TEMP_DIR="${TARGET_DIR}_zfs_temp_$$"

# 事前チェック
if [ "$(id -u)" -ne 0 ]; then
  echo "エラー: このスクリプトはroot権限で実行する必要があるのじゃ。" >&2; exit 1
fi
if [ ! -d "$TARGET_DIR" ]; then
  echo "エラー: 指定されたディレクトリ '$TARGET_DIR' が存在せんぞ。" >&2; exit 1
fi
if [ -n "$(ls -A "$TARGET_DIR")" ]; then
  echo "注意: ディレクトリ '$TARGET_DIR' は空ではない。データを一時的に移動するぞ。"
fi
if zfs list "$ZFS_DATASET" &>/dev/null; then
  echo "エラー: データセット '$ZFS_DATASET' はすでに存在するではないか。" >&2; exit 1
fi

# メイン処理
echo "--- ZFSデータセット変換を開始する ---"
echo "1. 元のディレクトリを一時的に改名する..."; mv "$TARGET_DIR" "$TEMP_DIR" || { echo "エラー: ディレクトリの改名に失敗した。終了する。" >&2; exit 1; }
echo "   '$TARGET_DIR' -> '$TEMP_DIR'"
echo "2. 新しいZFSデータセットを作成する..."; echo "   データセット: $ZFS_DATASET"; echo "   マウントポイント: $TARGET_DIR"; echo "   圧縮設定: $COMPRESSION_SETTING"
if [ "$COMPRESSION_SETTING" = "inherit" ]; then
  zfs create -o mountpoint="$TARGET_DIR" "$ZFS_DATASET"
else
  zfs create -o compression="$COMPRESSION_SETTING" -o mountpoint="$TARGET_DIR" "$ZFS_DATASET"
fi
if [ $? -ne 0 ]; then
  echo "エラー: ZFSデータセットの作成に失敗した！" >&2; echo "変更を元に戻す..."; mv "$TEMP_DIR" "$TARGET_DIR"; exit 1
fi
echo "3. データを新しいデータセットに移動する..."; shopt -s dotglob; mv "$TEMP_DIR"/* "$TARGET_DIR"/ || { echo "警告: データの一部の移動に失敗したかもしれん。" >&2; echo "一時ディレクトリ '$TEMP_DIR' は残しておくからのう、手動で確認せい。" >&2; }; shopt -u dotglob
if [ -z "$(ls -A "$TEMP_DIR")" ]; then
    echo "4. 一時ディレクトリを削除する..."; rmdir "$TEMP_DIR"
fi
echo "--- 完了 ---"; echo "ディレクトリ '$TARGET_DIR' は、データセット '$ZFS_DATASET' として正常に変換されたぞ。"; exit 0
