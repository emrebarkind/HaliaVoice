#!/bin/bash
# Plays one short phone call against the mock HALIA, the way the voice service would, and checks the result.
# Start the mock first (see README.md), then run: ./try-it.sh
# Needs bash, curl and node. Stops at the first unexpected answer.
set -euo pipefail
BASE="${MOCK_URL:-http://127.0.0.1:4010}"
TOKEN="${MOCK_HALIA_API_TOKEN:-try-the-format-0001}"
CONV=conv_demo_eco_0003
SESSION="vs_try_$(date +%s)"
VOICE="$BASE/v1/conversations/$CONV/voice-sessions/$SESSION"
REPLY=""  # HALIA's last reply; set by turn()

fail() { echo "FAILED: $*" >&2; exit 1; }

# request METHOD URL [BODY] [IDEMPOTENCY_KEY] -> prints the body; fails on a connection error or a non-2xx status
request() {
  local out status
  out=$(curl -sS --max-time 10 -X "$1" "$2" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' \
    ${3:+-H 'Content-Type: application/json' -d "$3"} ${4:+-H "Idempotency-Key: $4"} -w $'\n%{http_code}') \
    || fail "no answer from $2 (is the mock running on $BASE?)"
  status=${out##*$'\n'}
  out=${out%$'\n'*}
  [[ $status == 2* ]] || fail "HTTP $status from $2: $out"
  printf '%s' "$out"
}

# json EXPRESSION < body -> prints the value of a JavaScript expression over the parsed body `b`
json() { node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const b=JSON.parse(s);console.log($1)})"; }

event() { # $1 eventId suffix, $2 type, $3 data
  local body out
  body="{\"eventId\":\"evt_try_$1_$SESSION\",\"type\":\"$2\",\"occurredAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"data\":$3}"
  echo ">>> event $body"
  out=$(request POST "$VOICE/events" "$body") || exit 1
  echo "<<< $out"
  echo
}

# turn TURN_SEQ BODY [retry] -> sends one utterance, stores HALIA's reply in REPLY and reports its delivery.
# A retry gets no second delivery event: the voice service reports each reply once.
turn() {
  local id="turn_try_000$1" rid
  echo ">>> $2"
  REPLY=$(request POST "$VOICE/turns" "$2" "$id") || exit 1
  echo "<<< $REPLY"
  echo
  [[ ${3:-} == retry ]] && return
  rid=$(json 'b.responseId' <<<"$REPLY")
  event "delivery_$1" response.delivery "{\"responseId\":\"$rid\",\"turnId\":\"$id\",\"status\":\"sent_for_playback\"}"
}
say() { # $1 turnSeq, $2 what the patient said, $3 responseId of HALIA's previous reply, [$4 retry]
  turn "$1" "{\"turnId\":\"turn_try_000$1\",\"turnSeq\":$1,\"input\":{\"type\":\"speech\",\"text\":\"$2\",\"language\":\"it-IT\"},\"previousResponse\":{\"responseId\":\"$3\",\"status\":\"sent_for_playback\"}}" "${4:-}"
}

request POST "$BASE/_mock/reset" >/dev/null

echo "== The patient answers the phone"
event answered call.answered '{"twilioCallSid":"CA00000000000000000000000000000001","relaySessionId":"VX00000000000000000000000000000001"}'
turn 0 '{"turnId":"turn_try_0000","turnSeq":0,"input":{"type":"call_started","language":"it-IT"},"session":{"voiceHandoffToken":"vht_demo_c4e2a91f07b35d6e8a10","locale":"it-IT","call":{"direction":"outbound"},"startedAt":"2026-10-27T10:00:00.000Z"}}'
say 1 "Sì, va bene." rsp_0001
say 2 "Via Dante." rsp_0002

echo "== A correction inside one utterance: HALIA interprets it (live calls can also split it over several turns)"
say 3 "Martedì mattina, anzi, giovedì pomeriggio." rsp_0003
say 4 "Sì, confermo." rsp_0004
first=$REPLY

echo "== The same turnId again (a network retry): same answer, no second booking"
say 4 "Sì, confermo." rsp_0004 retry
[[ "$first" == "$REPLY" ]] || fail "the retried turn got a different answer"

say 5 "No, grazie." rsp_0005
[[ $(json 'b.actions.endCall' <<<"$REPLY") == true ]] || fail "HALIA did not end the call after the goodbye"

echo "== The call ends: the voice service reports it"
event completed call.completed '{"reason":"halia_end_call","durationSeconds":60,"turns":6}'

echo "== What the mock HALIA recorded"
state=$(request GET "$BASE/_mock/state") || exit 1
conv="b.conversations.find(x=>x.conversationId==='$CONV')"
bookings=$(json "b.appointments.filter(a=>a.conversationId==='$CONV').length" <<<"$state")
slot=$(json "b.appointments.filter(a=>a.conversationId==='$CONV').map(a=>a.slotId).join(',')" <<<"$state")
status=$(json "$conv.process.status" <<<"$state")
channel=$(json "$conv.activeChannel" <<<"$state")
summary=$(json "$conv.history.filter(h=>h.simulated).map(h=>h.text).join(' | ')" <<<"$state")
events=$(json "b.events.filter(e=>e.conversationId==='$CONV'&&!e.duplicate).map(e=>e.type).join(',')" <<<"$state")
deliveries=$(json "b.events.filter(e=>e.conversationId==='$CONV'&&e.type==='response.delivery').length" <<<"$state")
echo "Bookings:        $bookings ($slot)"
echo "Process:         $status"
echo "Active channel:  $channel"
echo "WhatsApp after:  $summary"
echo "Events:          $events"
[[ $bookings == 1 ]] || fail "expected exactly one booking, found $bookings"
[[ $slot == slot_eco_2026-11-05_pomeriggio_Via_Dante ]] \
  || fail "the booking is not for the corrected day and centre (giovedì 5 novembre, pomeriggio, Via Dante): $slot"
[[ $status == completed ]] || fail "the process is not completed"
[[ $channel == whatsapp ]] || fail "the conversation did not go back to WhatsApp"
[[ -n $summary ]] || fail "no simulated WhatsApp summary was recorded"
[[ $events == call.answered,*,call.completed ]] || fail "unexpected event order: $events"
[[ $deliveries == 6 ]] || fail "expected one delivery event per reply (6), found $deliveries"
echo
echo "OK: one booking for giovedì 5 novembre pomeriggio at Via Dante, the retry did not book twice, every reply's"
echo "delivery and the call status were recorded, and the conversation is back on WhatsApp with a summary."
