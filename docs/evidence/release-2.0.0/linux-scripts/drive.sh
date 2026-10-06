#!/bin/bash
# Runs the Linux evidence for one exact commit. Each work-* directory is a fresh 'git archive d6eb66f23641e2f7fb7e7dc6ea6dd8e324bd17f6' copy.
R="$(cd "$(dirname "$0")" && pwd)"
COMMIT=d6eb66f23641e2f7fb7e7dc6ea6dd8e324bd17f6
run() { name=$1 image=$2 script=$3 work=$4
  { echo "== commit $COMMIT (git archive copy)"; echo "== $name image=$image id=$(docker image inspect --format '{{.Id}}' $image)"; echo "== docker $(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}')"; } > "$R/logs/$name.log"
  docker run --rm --platform linux/arm64 -v "$R/work-$work:/work" -v "$R/out-$work:/out" -v "$R/$script:/run.sh:ro" -v "$R/cases.sh:/cases.sh:ro" -v "$R/fixtures:/fixtures:ro" "$image" bash /run.sh >> "$R/logs/$name.log" 2>&1
  echo "DOCKER-EXIT $name=$?" >> "$R/logs/$name.log"
}
run swift-6.0.3 swift:6.0-noble run-swift.sh swift60 &
run swift-6.3.3 swift:6.3-noble run-swift.sh swift63 &
run rust rust:1.95-bookworm run-rust.sh rust &
run typescript oven/bun:1.4 run-js.sh js &
wait
run interchange threemd-linux-interchange:local run-interchange.sh interchange
echo ALL-DONE > "$R/logs/done"
