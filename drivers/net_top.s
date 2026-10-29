; net_top.s - trail-net: the NET file as INDEPENDENCE builds it (its independence/src/net_top.s): the three drivers, the
; Uthernet II's addresses at a fixed place in the file (NET.CFG: NET SETUP in the game writes them there), and the
; main-memory block the file answers into. Ophis: ophis net_top.s -o NET.bin (build.sh).
.alias  NET_BUF $6824                   ; the client's 120-byte block in MAIN memory (NET-FILE.md): INDEPENDENCE's address
        .include "net.s"                ; the common part, the Super Serial Card, the Uthernet II, the CoGS card's first half
        .advance $3EDF                  ; NET.CFG: the file's last 25 bytes before the CoGS card's second half
nc_set: .byte 0                         ; 1 once NET SETUP has written the addresses
        .include "net_conf.inc"         ; nt_conf: gateway, mask, MAC, the Apple's IP, the server's IP and port (24 bytes)
        .include "net_cogs.s"           ; the CoGS card's second half
