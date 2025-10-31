# Linux-homebrew-scripts

個人用のシェルスクリプト集です。画像・動画の一括変換、整理、通知、環境設定、ZFS 変換などを自動化します。多くのスクリプトは `-h` または `--help` で使い方を表示します。

## 目次

- 概要
- 動作環境と実行前の準備
- スクリプト一覧（内容・依存関係・使い方）
- 共通の使い方と例
- 注意事項（重要）
- 貢献・ライセンス

---

## 概要

このリポジトリには、以下のカテゴリのスクリプトが含まれます。

- 画像変換・整理（ImageMagick / zopflipng）
- 動画エンコード・整理（ffmpeg / ffprobe）
- 通知（Discord Webhook）
- GNOME 壁紙スライドショー生成と適用（gsettings / apt）
- システム設定（GUI 起動ターゲット切替、/usr/local/bin へのリンク展開）
- ZFS データセット変換（zfs）

## 動作環境と実行前の準備

- 対応 OS: Linux（主に Ubuntu 系を想定）。WSL や他ディストリでも動くものがあります。
- シェル: bash もしくは sh（各ファイルの先頭 shebang を参照）。
- 実行権限を付与してください。

```bash
chmod +x *.sh
```

主な依存コマンド（スクリプトにより異なる）

- ffmpeg / ffprobe, ffplay, v4l2-ctl, arecord
- ImageMagick の convert（もしくは magick）
- zopflipng, curl, git
- rustup, cargo, meson, ninja, cmake, make, gcc 等（HandBrake ビルド）
- gsettings, apt（GNOME 関連）
- zfs（ZFS 関連）

## スクリプト一覧（内容・依存・使い方）

### Audio_File_Splitter.sh

- 内容: FFmpeg を使用して、指定ディレクトリ内の音声ファイルを指定秒数ごとに分割。出力形式は FLAC、WAV(16bit)、コピー（元の形式）から選択可能。単一ファイルまたは一括処理に対応。
- 使い方: `./Audio_File_Splitter.sh <入力ディレクトリ> [ファイル名]`（単一）、または `-b` オプションで一括処理。`-h`/`--help` で詳細。
- 依存: ffmpeg。
- オプション:
  - `-b, --batch`: 一括処理モード
  - `-d, --duration <秒>`: 分割時間（デフォルト: 600秒）
  - `-f, --format <形式>`: 出力形式（flac/wav_16bit/copy、デフォルト: wav_16bit）
  - `-p, --prefix <接頭辞>`: 分割後のファイル名接頭辞（デフォルト: split_）
  - `-r, --delete-original`: 成功時に元ファイルを削除（デフォルト: オン）
  - `--no-delete`: 元ファイルを削除しない
  - `-i, --install-ffmpeg`: FFmpeg を自動インストール（sudo 必要）
- 備考: 元ファイルは成功時にデフォルトで削除されます。`--no-delete` で無効化できます。

### BootAnimation-zopflipng.sh

- 内容: カレントディレクトリの PNG を `zopflipng -m` で最適化。
- 使い方: 引数なしで実行。`-h`/`--help` でヘルプ。
- 依存: zopflipng。
- 備考: 現在の実装はファイル名の末尾に `s` を付けて処理しています（意図と異なる可能性あり）。

### capture.sh

- 内容: 対話式のキャプチャ支援。動画デバイス/解像度/フレームレート、音声デバイス、コーデック（H.264/AV1/VP9、FLAC/Opus/MP3）を選んで「録画」または「プレビュー」を実行。
- 使い方: 引数なしで実行して選択を進める。`-h`/`--help` で説明。
- 依存: v4l2-ctl, arecord, ffmpeg, ffplay, awk/grep/sed。

### Discord_Message.sh

- 内容: `.env`（同ディレクトリ）から `DISCORD_WEBHOOK_URL` を読み込み、引数のメッセージを Discord Webhook へ送信。
- 使い方: `./Discord_Message.sh メッセージ...`（複数引数は改行連結）。`-h`/`--help` で説明。
- 依存: curl。
- 設定: `.env` に `DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."` を記載。

### ffmpegbulkEncode.sh

- 内容: 指定拡張子の動画を HEVC（Intel QSV: hevc_qsv）で一括エンコード。既に HEVC のファイルはスキップ。メタデータを保持し、元ファイルは削除。
- 使い方: `./ffmpegbulkEncode.sh <拡張子> [出力フォルダ]`（例: `mov ffmpeg`）。`-h`/`--help` で説明。
- 依存: ffmpeg, ffprobe（QSV 利用環境を推奨）。
- 備考: 一時フォルダに `/mnt/ramdisk/ffmpeg` があれば利用。終了時に LINE 通知スクリプト（`~/shellscript/LINEmessage.sh`）を呼びます（環境に無ければ無効化推奨）。

### File-All-deletion.sh

- 内容: カレント以下の全「ファイル」を `shred -uvz` で復元不能に削除（ディレクトリ構造は残る）。実行前に `yes` 確認あり。
- 使い方: 引数なしで実行。`-h`/`--help` で説明。
- 注意: 取り返しがつきません。テスト用ディレクトリで動作確認してください。

### GboardConvert.sh

- 内容: 指定ファイル内の `\tja-JP` を `\t名詞\t` に置換。`_convert` を付けた新ファイルとして出力。
- 使い方: `./GboardConvert.sh <ファイルパス>`。`-h`/`--help` で説明。
- 依存: sed。

### GNOME_create_slideshow.sh

- 内容: 指定フォルダの画像から GNOME 壁紙用スライドショー XML を生成し、`gsettings` で適用。`gnome-tweaks` 未導入なら `apt` でインストールを試行。
- 使い方: `./GNOME_create_slideshow.sh <画像フォルダ>`。`-h`/`--help` で説明。
- 依存: find, gsettings,（必要に応じて）apt, gnome-tweaks。
- 注意: `sudo` が必要になる場合があります。Ubuntu 系想定です。

### h264Move.sh

- 内容: 指定拡張子の動画のうち HEVC でないものを出力フォルダへ移動（HEVC のものはスキップ）。
- 使い方: `./h264Move.sh <拡張子> [出力フォルダ]`（デフォルト `Move`）。`-h`/`--help`。
- 依存: ffprobe, bash。

### HandBrake-Build.sh

- 内容: HandBrake の Windows 向け CUI を Linux 上でクロスビルドするための環境構築とビルド（rustup/cargo、MinGW、依存関係導入、リポジトリ clone, build）。
- 使い方: 引数なしで実行。`-h`/`--help` で説明。
- 依存: apt, git, rustup/cargo, cmake, ninja, meson, gcc 等。ネットワークと時間が必要。`sudo` 必須。

### ImageMagickConvertWEBP.sh

- 内容: カレントの jpg/jpeg/png/bmp を WebP（quality=70）へ変換し、元ファイルを削除。タイムスタンプ維持。
- 使い方: 引数なしで実行。`-h`/`--help` で説明。
- 依存: ImageMagick（convert）。

### ImgConvert180daysago-tast.sh

- 内容: カレントで 180 日以上前更新の jpg を抽出し、`ls180.txt` に追記。全ファイル一覧は `lsフル.txt` に保存（変換は行わないテスト版）。
- 使い方: 引数なし。`-h`/`--help` で説明。
- 備考: 終了時に LINE 通知スクリプトを呼びます。

### ImgConvert180daysago.sh

- 内容: 180 日以上前更新の jpg/jpeg/png/bmp を WebP（quality=90）へ変換し、元ファイルを削除。タイムスタンプ維持。
- 使い方: 引数なし。`-h`/`--help` で説明。
- 依存: ImageMagick（convert）。終了時に LINE 通知スクリプトを呼びます。

### MoveParentFolder.sh

- 内容: 指定フォルダ内のファイル・隠しファイルを 1 つ上の階層（カレント）へ移動後、空になったフォルダを削除。
- 使い方: `./MoveParentFolder.sh <対象フォルダ>`。`-h`/`--help` で説明。
- 注意: 上書きの可能性に留意してください（mv のオプション変更で安全化可能）。

### RunSubfolder.sh

- 内容: 直下サブディレクトリを列挙し、各ディレクトリ内で指定スクリプトを同じ引数で実行。
- 使い方: `./RunSubfolder.sh <実行スクリプト> [引数...]`。`-h`/`--help`。

### Set-GUI_Ubuntu.sh

- 内容: 対話式で Ubuntu のデフォルト起動ターゲットを GUI（graphical.target）/ CUI（multi-user.target）に切り替え。
- 使い方: 引数なしで実行し、`e`（有効）/`d`（無効）を入力。
- 依存: systemd（systemctl）。`sudo` が必要。

### SETUP.SH

- 内容: このディレクトリにある `.sh` へのシンボリックリンクを `/usr/local/bin` に展開・削除するインストーラ。リンク名は `Koa_*.sh`。
- 使い方: `sudo ./SETUP.SH -i`（インストール）、`sudo ./SETUP.SH -u`（アンインストール）、`-h`/`--help`。
- 依存: readlink, find, ln。`sudo` が必要。

### zfs_converter.sh

- 内容: 既存ディレクトリを ZFS データセットへ変換。元ディレクトリを一時退避→指定のデータセットを作成（圧縮設定含む）→マウントポイントに戻してデータを移動→権限復元。第 2 引数が `/` 終端なら「親データセット/ディレクトリ名-実行ユーザー」で名前自動生成。
- 使い方: `sudo ./zfs_converter.sh <対象ディレクトリ> <ZFSデータセット名|親データセット/> <圧縮設定>`（例は下記）。`-h`/`--help` 参照。
- 依存: zfs。`sudo` が必要。

## 共通の使い方と例

- 実行権限を付ける

```bash
chmod +x script.sh
```

- ヘルプを見る

```bash
./script.sh -h
./script.sh --help
```

- 例: 画像を WebP に一括変換（カレント）

```bash
./ImageMagickConvertWEBP.sh
```

- 例: 動画を HEVC(QSV) で一括変換

```bash
./ffmpegbulkEncode.sh mov ffmpeg
```

## 注意事項（重要）

- 破壊的操作: `File-All-deletion.sh` は復元不能な削除を行います。実行前に十分な確認を。
- 元ファイル削除: 画像/動画変換系は変換後に元ファイルを削除します（スクリプト本文参照）。
- 権限: `SETUP.SH`, `Set-GUI_Ubuntu.sh`, `HandBrake-Build.sh`, `zfs_converter.sh` などは `sudo` が必要です。
- 外部通知: 一部スクリプトは `~/shellscript/LINEmessage.sh` を呼びます。環境が無い場合は該当行をコメントアウトしてください。
- 動作確認: ディストリや環境差分により挙動が異なる場合があります。まずはテスト用ディレクトリで実行してください。

## 貢献・ライセンス

- 改善やバグ報告、ヘルプ整備の PR を歓迎します。再現手順や環境を添えてください。(やる気があれば)
- ライセンスは未指定です。

