# solana-tpu-quic is the TPU advertised in gossip +6
# Firedancer uses XDP for fast networking, which is not compatible with iptables (ufw)
#--------------------------------------------
#   TPU     QUIC  Client        Notes
#--------------------------------------------
#  8003  +6=8009  agave         default
#  9001  +6=9007  firedancer    useless
#  80**  +6=80**  jito-solana   dynamic TPU
#  8003  +6=8009  jito-relayer  when unstaked
# 11222 +6=11228  jito-relayer  when staked
#--------------------------------------------
