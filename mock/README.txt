HALIA Voice - mock HALIA
========================

A stand-in for HALIA that speaks the proposed message format. Synthetic data only;
nothing real is booked. It exercises the API only: no phone, no Twilio, no audio.

You need: Node.js (tested on version 24), bash and curl.


1. Start the mock (terminal 1, in this folder)

   MOCK_HALIA_API_TOKEN=try-the-format-0001 node mock-halia.mjs

   It listens on http://127.0.0.1:4010. Every request needs the header
   "Authorization: Bearer <token>" (GET /health needs none).


2. Play one call against it (terminal 2, in this folder)

   ./try-it.sh

   The script sends what the voice service would send during one call and prints
   each request (>>>) and the mock's answer (<<<):

   - the call is answered; the first message carries the handoff token and HALIA
     answers with the opening;
   - the patient gives the centre, then "Martedi mattina, anzi, giovedi pomeriggio"
     (the latest value wins) and confirms;
   - the same turnId is sent again, as after a network retry: same answer, no
     second booking;
   - the patient says goodbye; HALIA ends the call; the call status is reported.

   At the end it checks what HALIA recorded (one booking for the corrected day,
   process completed, conversation back on WhatsApp) and stops with "FAILED" if
   anything is wrong.

   Other port or token: MOCK_URL=http://127.0.0.1:4020 ./try-it.sh
                        MOCK_HALIA_API_TOKEN=<same value as the mock> ./try-it.sh


Endpoints

   POST /v1/conversations/{conversationId}/voice-sessions/{voiceSessionId}/turns
        one patient message in, HALIA's reply out (proposed)
   POST /v1/conversations/{conversationId}/voice-sessions/{voiceSessionId}/events
        call status (proposed)
   GET  /_mock/state, POST /_mock/reset, POST /_mock/faults
        mock controls only: recorded state, reset, inject errors
