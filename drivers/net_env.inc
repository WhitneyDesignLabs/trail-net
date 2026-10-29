; net_env.inc - trail-net: the two constants the NET file needs from its host. In INDEPENDENCE they are the engine's
; (drwplay.inc: the NET file is called through the game's picture player); a new client sets them here.
.alias  PL_NET  $3A00         ; where the NET file is loaded and entered (auxiliary memory; it may run to $3FFF)
.alias  P_SRC   $3C           ; the zero-page byte that holds the operation: 0 PROBE, 1 LINE, 2 NEXT, 3 CLOSE
