#!/bin/bash
#
# ZFSデータセット変換スクリプト
# 指定されたディレクトリをZFSデータセットに変換し、マウントポイントと圧縮設定を適用するスクリプトじゃ。
# UTF-8で保存すること
#

# --- ヘルプ表示関数 ---
show_help() {
    cat <<EOF
使い方: ${0##*/} <対象ディレクトリ> <ZFSデータセット名> <圧縮設定>

このスクリプトは既存のディレクトリをZFSデータセットに変換するもんじゃ。

引数:
    対象ディレクトリ    変換したいディレクトリのフルパスを指定する。
                        これが新しいデータセットのマウントポイントになるぞ。

    ZFSデータセット名   作成する新しいZFSデータセットの名前じゃ。
                        ★親データセット名の末尾に '/' を付けると、
                        「ディレクトリ名-ユーザー名」の形式でデータセット名を自動生成するぞ。

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
    gzip-1..9       : 数字が上がるほど高圧縮になるが、負荷も増す。

    --- Zstandard系アルゴリズム (高性能) ---
    zstd            : zstd-3 の別名。速度と圧縮のバランスが良い。
    zstd-1..19      : 標準レベル。数字が大きいほど高圧縮・高負荷じゃ。(例: zstd-1, zstd-10)
    zstd-fast-N     : 超高速レベル。圧縮率より速度を優先する。Nには1からの数字が入る。
    zstd-20..22     : ★注意★ 超高圧縮レベル。莫大なメモリを消費する！

    --- その他 ---
    zle             : ゼロの連続だけを圧縮する。非常に軽量で、特定のデータに有効。

実行例:
    # データセット名をフルで指定する場合
    sudo ${0##*/} /var/www/html tank/webdata off

    # 親データセットを指定して、データセット名を自動生成する場合 (ユーザー 'satori' が実行)
    sudo ${0##*/} /home/satori/projects rpool/USERDATA/homes/ lz4
    # -> 'rpool/USERDATA/homes/projects-satori' というデータセットが作成されるぞ。
EOF
}

# --- ここから下のスクリプト本体は変更なし ---

# 引数のチェック
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi
if [ "$#" -ne 3 ]; then
    echo "エラー: 引数が足りんのじゃ。3つ必要じゃ。" >&2
    echo ""
    show_help
    exit 1
fi

# 変数定義
TARGET_DIR=$(readlink -f "$1")
ZFS_DATASET_ARG="$2"
COMPRESSION_SETTING="$3"

# ★★★ ここから変更 ★★★
# データセット名の自動生成機能じゃ
if [[ "$ZFS_DATASET_ARG" == */ ]]; then
    # 引数の末尾が / なら、親データセットと見なす
    PARENT_DATASET=${ZFS_DATASET_ARG%/} # 末尾のスラッシュを削除
    NEW_DATASET_NAME=$(basename "$TARGET_DIR")
    EXEC_USER=""
    if [ -n "$SUDO_USER" ]; then
        EXEC_USER="$SUDO_USER"
    fi

    if [ -n "$EXEC_USER" ]; then
        ZFS_DATASET="${PARENT_DATASET}/${NEW_DATASET_NAME}-${EXEC_USER}"
        echo "INFO: 親データセット '${PARENT_DATASET}' を元に、ディレクトリ名とユーザー名から '${ZFS_DATASET}' を自動生成したぞ。"
    else
        ZFS_DATASET="${PARENT_DATASET}/${NEW_DATASET_NAME}"
        echo "INFO: 親データセット '${PARENT_DATASET}' を元に、データセット名 '${ZFS_DATASET}' を自動生成したぞ。"
        echo "WARN: sudoを実行したユーザー名が取得できんかったため、サフィックスは付かんぞ。" >&2
    fi
else
    # / で終わらない場合は、これまで通り完全なデータセット名として扱う
    ZFS_DATASET="$ZFS_DATASET_ARG"
fi
# ★★★ ここまで変更 ★★★

TEMP_DIR="${TARGET_DIR}_zfs_temp_$$"

# 事前チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトはroot権限で実行する必要があるのじゃ。" >&2
    exit 1
fi
if [ ! -d "$TARGET_DIR" ]; then
    echo "エラー: 指定されたディレクトリ '$TARGET_DIR' が存在せんぞ。" >&2
    exit 1
fi

# 元のディレクトリの所有者と権限を保存するのじゃ
ORIGINAL_OWNER=$(stat -c %u:%g "$TARGET_DIR")
ORIGINAL_PERMS=$(stat -c %a "$TARGET_DIR")
echo "INFO: 元のディレクトリの所有者($ORIGINAL_OWNER)と権限($ORIGINAL_PERMS)を記録したぞ。"

if [ -n "$(ls -A "$TARGET_DIR")" ]; then
    echo "注意: ディレクトリ '$TARGET_DIR' は空ではない。データを一時的に移動するぞ。"
fi

if zfs list "$ZFS_DATASET" &>/dev/null; then
    echo "エラー: データセット '$ZFS_DATASET' はすでに存在するではないか。" >&2
    exit 1
fi

# メイン処理
echo "--- ZFSデータセット変換を開始する ---"
echo "1. 元のディレクトリを一時的に改名する..."
mv "$TARGET_DIR" "$TEMP_DIR" || {
    echo "エラー: ディレクトリの改名に失敗した。終了する。" >&2
    exit 1
}
echo "   '$TARGET_DIR' -> '$TEMP_DIR'"
echo "2. 新しいZFSデータセットを作成する..."
echo "   データセット: $ZFS_DATASET"
echo "   マウントポイント: $TARGET_DIR"
echo "   圧縮設定: $COMPRESSION_SETTING"
if [ "$COMPRESSION_SETTING" = "inherit" ]; then
    zfs create -o mountpoint="$TARGET_DIR" "$ZFS_DATASET"
else
    zfs create -o compression="$COMPRESSION_SETTING" -o mountpoint="$TARGET_DIR" "$ZFS_DATASET"
fi
if [ $? -ne 0 ]; then
    echo "エラー: ZFSデータセットの作成に失敗した！" >&2
    echo "変更を元に戻す..."
    mv "$TEMP_DIR" "$TARGET_DIR"
    exit 1
fi

echo "2.5. 新しいデータセットに元の所有者と権限を適用する..."
chown "$ORIGINAL_OWNER" "$TARGET_DIR" || echo "警告: 所有者の変更に失敗したかもしれん。" >&2
chmod "$ORIGINAL_PERMS" "$TARGET_DIR" || echo "警告: 権限の変更に失敗したかもしれん。" >&2

echo "3. データを新しいデータセットに移動する..."
shopt -s dotglob
mv "$TEMP_DIR"/* "$TARGET_DIR"/ || {
    echo "警告: データの一部の移動に失敗したかもしれん。" >&2
    echo "一時ディレクトリ '$TEMP_DIR' は残しておくからのう、手動で確認せい。" >&2
}
shopt -u dotglob
if [ -z "$(ls -A "$TEMP_DIR")" ]; then
    echo "4. 一時ディレクトリを削除する..."
    rmdir "$TEMP_DIR"
fi
echo "--- 完了 ---"
echo "ディレクトリ '$TARGET_DIR' は、データセット '$ZFS_DATASET' として正常に変換されたぞ。"
exit 0
