# 実装履歴

## 2026-05-11

### 依存コマンド事前チェックの追加
- 追加導入が必要なコマンドを、各スクリプトの実行前に検証する `require_commands` を導入。
- 不足コマンドがある場合は、対象コマンド名を表示して即時終了する動作を追加。
- 既存で依存チェックがあったスクリプトは、追加不足分のみ補強。

### 対象スクリプト
- BootAnimation-zopflipng.sh
- capture.sh
- Convert-GboardDictionary.sh
- Demucs_concat_flac_segments.sh
- Demucs_create_multitrack_webm.sh
- Demucs_prepare_segments.sh
- Discord_Message.sh
- ffmpegbulkEncode.sh
- File-All-deletion.sh
- GboardConvert.sh
- GNOME_create_slideshow.sh
- h264Move.sh
- HandBrake-Build.sh
- ImageMagickConvertWEBP.sh
- ImgConvert180daysago.sh
- ImgConvert180daysago-tast.sh
- MoveParentFolder.sh
- optimize_apng.sh
- RunSubfolder.sh
- SETUP.SH
- Set-GUI_Ubuntu.sh
- update_mkv-webm_stats.sh
- zfs_converter.sh

### README 更新
- 依存コマンド一覧を実装内容に合わせて拡張（unzip / parallel / shred / compare / systemctl / xdg-* など）。
- 各スクリプトが事前依存チェックを行うことを明記。
- 一部スクリプト個別セクションの依存情報を修正。
