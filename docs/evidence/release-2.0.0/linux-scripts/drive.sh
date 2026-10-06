#!/bin/bash
R="$(cd "$(dirname "$0")" && pwd)"
run() { name=$1 image=$2 script=$3
  echo "== $name image=$image digest=$(docker image inspect --format '{{index .RepoDigests 0}}' $image 2>/dev/null || docker image inspect --format '{{.Id}}' $image)" > "$R/logs/$name.log"
  docker run --rm --platform linux/arm64 -v "$R/work-$4:/work" -v "$R/out-$4:/out" -v "$R/$script:/run.sh:ro" "$image" bash /run.sh >> "$R/logs/$name.log" 2>&1
  echo "DOCKER-EXIT $name=$?" >> "$R/logs/$name.log"
}
run swift-6.0.3 swift:6.0-noble run-swift.sh swift60 &
run swift-6.3.3 swift:6.3-noble run-swift.sh swift63 &
run rust rust:1.95-bookworm run-rust.sh rust &
run typescript oven/bun:1.4 run-js.sh js &
wait
run interchange threemd-linux-interchange:local run-interchange.sh interchange
echo ALL-DONE > "$R/logs/done"
