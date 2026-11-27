#!/bin/bash
# ネット上のロボット（GitHub Actions）が動かす投稿プログラム。
# queue/ の中から「投稿時刻が来たもの」を1本だけインスタに投稿し、state/posted.txt に記録します。
#
# 必要なもの（GitHubの設定に入れる）
#   秘密(Secrets)  IG_TOKEN … インスタ投稿用の合いカギ
#   変数(Variables) DRY_RUN … true なら試しモード（投稿しない）
set -uo pipefail

API="https://graph.instagram.com/${IG_API_VERSION:-v23.0}"
LATE_LIMIT=$((90 * 60))       # 予定時刻から90分以上たったものは投稿せず「見送り」にする
STATE=state/posted.txt
mkdir -p state queue
touch "$STATE"

now=$(date +%s)
failed=0

log()  { echo "$*"; }
fail() { echo "::error::$*"; failed=1; }

# 投稿を1本出す。成功したら MID にメディアIDが入る。
MID=""
publish() {
  local name=$1 caption url uid res cid status pub i
  caption=$(cat "queue/$name/caption.txt")
  url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/queue/${name}/image.jpg"

  uid=$(curl -sS -G "$API/me" --data-urlencode "fields=user_id,username" \
        --data-urlencode "access_token=$IG_TOKEN" | jq -r '.user_id // empty')
  [ -n "$uid" ] || { fail "$name: アカウント情報を取れませんでした（合いカギが切れている可能性）"; return 1; }

  res=$(curl -sS -X POST "$API/$uid/media" \
        --data-urlencode "image_url=$url" \
        --data-urlencode "caption=$caption" \
        --data-urlencode "access_token=$IG_TOKEN")
  cid=$(jq -r '.id // empty' <<<"$res")
  [ -n "$cid" ] || { fail "$name: 画像の受け付けに失敗：$(jq -c '.error // .' <<<"$res")"; return 1; }

  # インスタ側の準備ができるまで待つ（最大1分）
  for i in $(seq 1 12); do
    status=$(curl -sS -G "$API/$cid" --data-urlencode "fields=status_code" \
             --data-urlencode "access_token=$IG_TOKEN" | jq -r '.status_code // empty')
    [ "$status" = "FINISHED" ] && break
    [ "$status" = "ERROR" ] && { fail "$name: インスタ側で画像の処理に失敗しました"; return 1; }
    sleep 5
  done

  pub=$(curl -sS -X POST "$API/$uid/media_publish" \
        --data-urlencode "creation_id=$cid" \
        --data-urlencode "access_token=$IG_TOKEN")
  MID=$(jq -r '.id // empty' <<<"$pub")
  [ -n "$MID" ] || { fail "$name: 公開に失敗：$(jq -c '.error // .' <<<"$pub")"; return 1; }
}

for dir in $(ls -d queue/*/ 2>/dev/null | sort); do
  name=$(basename "$dir")                       # 例：2026-12-03_0800
  [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$ ]] || continue
  grep -q "^$name " "$STATE" && continue        # 投稿済み・見送り済み

  d=${name%_*}; t=${name#*_}
  due=$(TZ=Asia/Tokyo date -d "$d ${t:0:2}:${t:2:2}" +%s)
  [ "$due" -gt "$now" ] && continue             # まだ時間前

  if [ $((now - due)) -gt $LATE_LIMIT ]; then
    echo "$name skipped $(date -u +%FT%TZ)" >> "$STATE"
    fail "$name: 予定時刻を90分以上過ぎていたので投稿を見送りました"
    continue
  fi

  if [ "${DRY_RUN:-true}" != "false" ]; then
    log "【試しモード】$name を投稿するところでした（実際には投稿していません）"
    log "  画像：https://raw.githubusercontent.com/${REPO}/${BRANCH}/queue/${name}/image.jpg"
    log "  投稿文の1行目：$(head -1 "queue/$name/caption.txt")"
    break
  fi

  [ -n "${IG_TOKEN:-}" ] || { fail "合いカギ IG_TOKEN が設定されていません"; break; }
  if publish "$name"; then
    echo "$name posted $(date -u +%FT%TZ) $MID" >> "$STATE"
    log "投稿しました：$name（メディアID $MID）"
  fi
  break                                         # 1回の実行で投稿するのは1本だけ
done

exit $failed
