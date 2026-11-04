-- LedgerData.lua
-- The Forever Duo Ledger writes this file when you press "Send to game".
-- The game only ever reads it (at login and /reload), and the Ledger only
-- ever writes it, so the two never fight over the same file. That's why
-- it's safe to send while you're playing: just /reload afterwards.
--
-- Until you send something, there's no Ledger data yet.
DuoLedgerLedgerData = nil
