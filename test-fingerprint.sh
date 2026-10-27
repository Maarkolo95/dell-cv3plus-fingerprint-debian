#!/bin/bash
# Checks fingerprint recognition 5 times and reports how many matched.
# Run with:  bash test-fingerprint.sh            (right index finger)
#            bash test-fingerprint.sh left-index-finger
FINGER=${1:-right-index-finger}
ok=0
for i in 1 2 3 4 5; do
  echo
  echo ">>> Test $i/5: touch the sensor with your $FINGER (press flat, hold ~1 s)"
  if fprintd-verify -f "$FINGER" 2>&1 | tee /dev/stderr | grep -q 'verify-match'; then
    ok=$((ok+1)); echo "    MATCH"
  else
    echo "    no match"
  fi
  sleep 1
done
echo
echo "RESULT: $ok of 5 matched for $FINGER"
