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
- APNG アニメーション最適化
- 通知（Discord Webhook）
- GNOME 壁紙スライドショー生成と適用（gsettings / apt）
- システム設定（GUI 起動ターゲット切替、/usr/local/bin へのリンク展開）
- ZFS データセット変換（zfs）
- Demucs 前後処理（音源分割・分離後の連結）

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
- zopflipng, apngdis, apngasm
- curl, git
- rustup, cargo, meson, ninja, cmake, make, gcc 等（HandBrake ビルド）
- gsettings, apt（GNOME 関連）
- zfs（ZFS 関連）

## スクリプト一覧（内容・依存・使い方）

### Demucs ワークフロー（推奨手順）

1) 事前分割（長尺対策・安定化）
   - [Demucs_prepare_segments.sh](Demucs_prepare_segments.sh)
   - 内容: 長尺の音源を一定秒数で分割（デフォルト 600 秒）。Demucs 実行を安定化。
   - 使い方:

     ```bash
     ./Demucs_prepare_segments.sh /path/to/audio -b -d 600 -f wav_16bit
     ```

2) Demucs 分離の実行
   - 例: 分割済みファイル群に対し demucs を実行（モデルは環境に合わせて選択）

     ```bash
     demucs -n htdemucs_ft split_*
     ```

3) 分離結果の連結（separated/htdemucs_ft/ 内で実行）
   - [Demucs_concat_flac_segments.sh](Demucs_concat_flac_segments.sh)
   - 内容: split_ベース名_XXX ディレクトリから vocals.flac / minus_vocals.flac をベース名ごとに連結。
   - 使い方:

     ```bash
     cd separated/htdemucs_ft
     ../../Demucs_concat_flac_segments.sh
     ```

### Demucs_prepare_segments.sh

- 内容: FFmpeg で指定ディレクトリ内の音声ファイルを一定秒数で分割。Demucs 前処理として長尺音源を分割する用途を想定。
- 使い方: `./Demucs_prepare_segments.sh <入力ディレクトリ> [ファイル名]`、または `-b` で一括処理。`-h`/`--help` でヘルプ表示。
- 依存: ffmpeg。
- 主なオプション:
  - `-b, --batch` 一括処理
  - `-d, --duration <秒>` 分割時間（既定: 600）
  - `-f, --format <形式>` 出力形式（flac/wav_16bit/copy、既定: wav_16bit）
  - `-p, --prefix <接頭辞>` 接頭辞（既定: split_）
  - `-r, --delete-original` 成功時に元ファイルを削除（既定: オン）
  - `--no-delete` 元ファイルを削除しない
  - `-i, --install-ffmpeg` sudo apt で ffmpeg をインストール

### Demucs_concat_flac_segments.sh

- 内容: `separated/htdemucs_ft/` 直下で、`split_ベース名_XXX` ディレクトリ群に含まれる `vocals.flac` と `minus_vocals.flac` を、ベース名ごとに連結。Demucs 分離後の後処理として使用。
- 使い方:

  ```bash
  cd separated/htdemucs_ft
  ../../Demucs_concat_flac_segments.sh
  ```

  `-h` または `--help` でヘルプ表示。
- 依存: ffmpeg, sort (GNU sort の `sort -V`)。
- 備考: 連結後、元の分割ディレクトリを削除するか確認プロンプトが表示されます。

### Audio_File_Splitter.sh

- 備考: 本スクリプトは [Demucs_prepare_segments.sh](Demucs_prepare_segments.sh) に名称変更されました（機能は同等）。旧名での参照は非推奨です。

### concat_flac_segments.sh

- 備考: 本スクリプトは [Demucs_concat_flac_segments.sh](Demucs_concat_flac_segments.sh) に名称変更されました（機能は同等）。旧名での参照は非推奨です。

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

### optimize_apng.sh

- 内容: APNG ファイルを分解し、類似した重複フレーム（連続フレームおよびループ始終端）を削除して軽量化・最適化します。処理途中でフォルダを開き、手動でのフレーム削除も可能です。
- 使い方:
  - 最適化版の作成: `./optimize_apng.sh <入力ファイル.png>`
  - 適用（上書き）: `./optimize_apng.sh -d` (カレントディレクトリの `*-optimize.apng` を元ファイルに適用)
- 依存: apngdis, apngasm, imagemagick (compare), xdg-open

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
