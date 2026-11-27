# 偉人の言葉帳 投稿ロボット

インスタグラム @meigen_shigoto に、決まった時間（毎日 8時・12時・22時）に自動で投稿する仕組みです。

- `queue/日付_時刻/` … 投稿待ちの画像（image.jpg）と投稿文（caption.txt）
- `state/posted.txt` … 投稿した記録
- `bot/post_due.sh` … 投稿プログラム
- `.github/workflows/` … 動かす時間の設定

画像と投稿文は、インスタに公開するためのものだけを置いています。
